import 'package:cloud_firestore/cloud_firestore.dart' as cf;

import 'package:firestore_olmps/src/defs/document.dart';
import 'package:firestore_olmps/src/defs/errors.dart';
import 'package:firestore_olmps/src/defs/query_filter.dart';
import 'package:firestore_olmps/src/defs/query_sort.dart';
import 'package:firestore_olmps/src/paginated.dart';

import 'package:meta/meta.dart' show protected;

/// Firestore implementation for an atomic database transaction.
///
/// Currently, there is no support for multiple transactions running simultaneously. If necessary, run a transaction
/// once, then run another after completing the first one.
/// 
/// Firestore transaction limitations must be taken into consideration and will throw [TransactionError] if not
/// respected.
abstract class FirestoreTransactionHandler {
  FirestoreTransactionHandler(this.firestore);

  @protected
  final cf.FirebaseFirestore firestore;

  @protected
  cf.Transaction? currentTransaction;
  
  /// Wrap [run] in a [cf.Transaction].
  /// 
  /// Throws an [UnsupportedError] if multiple transactions are ran in parallel.
  /// 
  /// Throws a [TransactionError] if anything is thrown while running the transaction callback.
  Future<void> runInTransaction(Future<void> Function() run) async {
    if (currentTransaction != null) {
      throw UnsupportedError('Trying to run a new transaction while there is one already running');
    }

    try {
      await firestore.runTransaction((transaction) async {
        currentTransaction = transaction;
        await run();
      });
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      // Not able to keep stack-trace while wrapping in a new error. https://github.com/dart-lang/sdk/issues/10297
      throw TransactionError('Failed transaction with StackTrace:\n${stack.toString()}', error);
    } finally {
      currentTransaction = null;
    }
  }
}

/// Abstract operations that are compliant with NoSQL document databases APIs, although heavily influenced by
/// [cf.FirebaseFirestore] implementation.
abstract class DocumentDatabase extends FirestoreTransactionHandler {
  DocumentDatabase(cf.FirebaseFirestore firestore) : super(firestore);

  /// Get all docs in the collection [collectionPath].
  ///
  /// The fetch can be filtered by passing [filters] and sorted by [sorts].
  ///
  /// Optionally, it can add a maximum [limit] to these results.
  Future<List<Document>> getAll({
    required String collectionPath,
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    int? limit,
  });

  /// Get all docs in multiple collections that shared the same name [collectionGroup].
  ///
  /// The fetch can be filtered by passing [filters] and sorted by [sorts].
  ///
  /// Optionally, it can add a maximum [limit] to these results.
  Future<List<Document>> getAllByGroup({
    required String collectionGroup,
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    int? limit,
  });

  /// Get all docs in the collection [collectionPath] using a cursor-pagination strategy.
  ///
  /// [pageSize] defines how many documents are fetched per load.
  ///
  /// [resultDeserializer] serializes the fetched documents.
  ///
  /// [listenToChanges] defines whether it should listen for retrieved document changes.
  ///
  /// The fetch can be filtered by passing [filters] and sorted by [sorts].
  ///
  /// See also:
  ///   - [CursorPaginatedResult], the structure that controls the pagination "actions".
  CursorPaginatedResult<T> getAllPaginated<T>({
    required String collectionPath,
    required int pageSize,
    required DocumentDeserializer<T> resultDeserializer,
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    bool listenToChanges,
  });

  /// Create a listening stream to all docs in the collection [collectionPath].
  ///
  /// An optional list of [filters] and [sorts] may be provided.
  ///
  /// Also, if [limit] is provided, limits the total results returned by this fetch.
  Stream<List<Document>> listenTo({
    required String collectionPath,
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    int? limit,
  });

  /// Create a listening stream to changes in the document [id], stored in [collectionPath].
  ///
  /// A `null` event may be emitted if the document doesn't exist or is - at any given moment - removed.
  Stream<Document?> listenToDocument({required String id, required String collectionPath});

  /// Get the document with [id], stored in collection [collectionPath]
  ///
  /// May return `null` if there is no such document.
  Future<Document?> get({required String id, required String collectionPath});

  /// Set (update or create) the document of key [id] with content [data] in collection [collectionPath].
  ///
  /// Merges [data] fields when document already exists, otherwise creates it.
  /// 
  /// [shouldMerge] specifies if existing fields, but not present in [data], should be merged.
  Future<void> set({required String collectionPath, required Map<String, dynamic> data, required String id, bool shouldMerge = true});

  /// Update the document of key [id] with content [data] in collection [collectionPath].
  ///
  /// If the some [data] fields already exist in Firestore, they are overridden, otherwise added. The same occurs to
  /// fields that exist in Firestore but aren't present in [data] - unless the name of the field is explicitly
  /// attributed to a null value.
  ///
  /// Contrary to [set], this operation will fail if there is no document at [collectionPath] with the [id] argument.
  Future<void> update({required String collectionPath, required String id, required Map<String, dynamic> data});

  /// Deletes the document with key [id] stored in collection [collectionPath]
  Future<void> delete({required String collectionPath, required String id});
}

class FirestoreDatabase extends DocumentDatabase {
  FirestoreDatabase(cf.FirebaseFirestore firestore) : super(firestore);

  @override
  Future<List<Document>> getAll({
    required String collectionPath,
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    int? limit,
  }) async {
    try {
      final query = _buildQuery(firestore.collection(collectionPath), filters: filters, sorts: sorts, limit: limit);
      final snapshot = await query.get();
      return snapshot.docs.map(_mapToFirestoreDocument).toList();
    } on cf.FirebaseException catch (exception) {
      throw FirestoreDatabaseError(
        'Failed to get all documents from collection "$collectionPath" with \nFilters: "$filters"\nSorts: "$sorts"\nLimit: $limit',
        exception,
      );
    }
  }

  @override
  Future<List<Document>> getAllByGroup({
    required String collectionGroup,
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    int? limit,
  }) async {
    try {
      final snapshot = await _buildQuery(
        firestore.collectionGroup(collectionGroup),
        filters: filters,
        sorts: sorts,
        limit: limit,
      ).get();

      return snapshot.docs.map(_mapToFirestoreDocument).toList();
    } on cf.FirebaseException catch (exception) {
      throw FirestoreDatabaseError(
        'Failed to get all documents from collection group "$collectionGroup" with \nFilters "$filters"\nSorts "$sorts"\nLimit: $limit',
        exception,
      );
    }
  }

  @override
  CursorPaginatedResult<T> getAllPaginated<T>({
    required String collectionPath,
    required int pageSize,
    required DocumentDeserializer<T> resultDeserializer,
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    bool listenToChanges = false,
  }) =>
      FirestorePaginatedResult(
        _buildQuery(firestore.collection(collectionPath), filters: filters, sorts: sorts),
        listenToChanges: listenToChanges,
        pageSize: pageSize,
        deserialize: resultDeserializer,
      );

  @override
  Stream<List<Document>> listenTo({
    required String collectionPath,
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    int? limit,
  }) =>
      _buildQuery(firestore.collection(collectionPath), filters: filters, sorts: sorts, limit: limit)
          .snapshots()
          .map((event) => event.docs.map(_mapToFirestoreDocument).toList())
          .handleError(
            (error, _) => throw FirestoreDatabaseError(
              'Failed to listen to documents of collection "$collectionPath" with \nFilters: "$filters"\nSorts: "$sorts"\nLimit: $limit',
              error,
            ),
          );

  @override
  Stream<Document?> listenToDocument({required String id, required String collectionPath}) => firestore
      .collection(collectionPath)
      .doc(id)
      .snapshots()
      .map((event) => event.exists ? _mapToFirestoreDocument(event) : null)
      .handleError(
        (error, _) => throw FirestoreDatabaseError(
          'Failed to listen to document with id "$id" in collection "$collectionPath"',
          error,
        ),
      );

  @override
  Future<Document?> get({required String id, required String collectionPath}) async {
    try {
      final documentRef = firestore.collection(collectionPath).doc(id);

      final operation = currentTransaction != null ? currentTransaction!.get(documentRef) : documentRef.get();
      final snapshot = await operation;
      return snapshot.exists ? _mapToFirestoreDocument(snapshot) : null;
    } on cf.FirebaseException catch (exception) {
      throw FirestoreDatabaseError('Failed to get document with id "$id" in collection "$collectionPath"', exception);
    }
  }

  @override
  Future<void> set({required String collectionPath, required Map<String, dynamic> data, required String id, bool shouldMerge = true}) async {
    try {
      final documentRef = firestore.collection(collectionPath).doc(id);

      await currentTransaction != null
          ? currentTransaction!.set(documentRef, data, cf.SetOptions(merge: shouldMerge))
          : documentRef.set(data, cf.SetOptions(merge: shouldMerge));
    } on cf.FirebaseException catch (exception) {
      throw FirestoreDatabaseError(
          'Failed to set document with id "$id" in collection "$collectionPath" with\nData: "$data"', exception);
    }
  }

  @override
  Future<void> update({required String collectionPath, required String id, required Map<String, dynamic> data}) async {
    try {
      final documentRef = firestore.collection(collectionPath).doc(id);
      await currentTransaction != null ? currentTransaction!.update(documentRef, data) : documentRef.update(data);
    } on cf.FirebaseException catch (exception) {
      throw FirestoreDatabaseError(
        'Failed to update document with id "$id" in collection "$collectionPath" with\nData: "$data"',
        exception,
      );
    }
  }

  @override
  Future<void> delete({required String collectionPath, required String id}) async {
    try {
      final documentRef = firestore.collection(collectionPath).doc(id);
      await currentTransaction != null ? currentTransaction!.delete(documentRef) : documentRef.delete();
    } on cf.FirebaseException catch (exception) {
      throw FirestoreDatabaseError(
          'Failed to delete document with id "$id" in collection "$collectionPath"', exception);
    }
  }


  /// Generic query building that uses [filters], [sorts] and an optional [limit].
  cf.Query _buildQuery(cf.Query query, {List<QueryFilter> filters = const [], List<QuerySort> sorts = const [], int? limit}) {
    cf.Query builtQuery = query;

    filters.forEach((filter) {
      builtQuery = builtQuery.where(
        filter.field,
        isEqualTo: filter.isEqualTo,
        isNotEqualTo: filter.isNotEqualTo,
        isLessThan: filter.isLessThan,
        isLessThanOrEqualTo: filter.isLessThanOrEqualTo,
        isGreaterThan: filter.isGreaterThan,
        isGreaterThanOrEqualTo: filter.isGreaterThanOrEqualTo,
        arrayContains: filter.arrayContains,
        arrayContainsAny: filter.arrayContainsAny,
        whereIn: filter.whereIn,
        whereNotIn: filter.whereNotIn,
        isNull: filter.isNull,
      );
    });

    sorts.forEach((sort) {
      builtQuery = builtQuery.orderBy(sort.field, descending: sort.descending);
    });

    if (limit != null) {
      builtQuery = builtQuery.limit(limit);
    }

    return builtQuery;
  }

  Document _mapToFirestoreDocument(cf.DocumentSnapshot<Object?> document) =>
      Document(document.id, document.data()! as Map<String, dynamic>);
}


