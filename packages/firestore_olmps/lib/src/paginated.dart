import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firestore_olmps/src/defs/document.dart';
import 'package:firestore_olmps/src/defs/errors.dart';


/// Abstract operations that allows manipulating a paginatable result from a database that uses cursors, although
/// heavily influenced by [cf.FirebaseFirestore] implementation.
abstract class CursorPaginatedResult<T> {
  /// Listen for updates in all loaded documents.
  bool get listenToChanges;

  /// Size for each batch of documents to-be-fetched in a pagination page.
  int get pageSize;

  /// Specifies if there are any more results that can be fetched.
  bool get hasMorePages;

  /// Emits a list of documents once new results are available.
  ///
  /// These events may be emitted after calling [loadNextPage] (if [hasMorePages] is still `true`).
  /// 
  /// Results may also emit a new list when previously-loaded documents are updated, if [listenToChanges] is `true`.
  Stream<List<T>> get results;

  /// Load the next page of this paginatable sets of results.
  ///
  /// This future resolves with all results fetched so far AND the next page of results appended to it. If listening to
  /// [results], one can ignore this response, as it will also trigger a new event with the same value.
  /// 
  /// Returns [allResults] if [hasMorePages] is `false` or there is an ongoing [loadNextPage].
  Future<List<T>> loadNextPage();

  /// Synchronously deserializes and return all results loaded up until now.
  List<T> getAllResults();

  /// Dispose of all streams and listeners associated with this instance.
  Future<void> dispose();
}

class FirestorePaginatedResult<T> implements CursorPaginatedResult<T> {
  FirestorePaginatedResult(
    this._query, {
    required this.listenToChanges,
    required this.pageSize,
    required this.deserialize,
  });

  final cf.Query _query;

  @override
  final bool listenToChanges;

  @override
  final int pageSize;

  @override
  Stream<List<T>> get results => _controller.stream;

  /// Controls the loaded results and expose them through [results] getter.
  final _controller = StreamController<List<T>>();

  @override
  bool get hasMorePages => _hasMorePages;
  bool _hasMorePages = true;

  final List<Document> _allResults = [];

  /// Deserialize function that transforms a [Document] into [T] type.
  final DocumentDeserializer<T> deserialize;

  /// Cursor reference to the last document fetched in [loadNextPage].
  cf.DocumentSnapshot? _cursorRef;

  /// If this instance has a pending [loadNextPage] fetch request.
  /// 
  /// When this is `true`, all further [loadNextPage] calls will return the latest [allResults].
  bool _isLoadingNextPage = false;
  
  List<StreamSubscription> _streamSubscriptions = [];

  @override
  Future<List<T>> loadNextPage() async {
    if (!_hasMorePages || _isLoadingNextPage) {
      return _deserializeAllResults();
    }

    _isLoadingNextPage = true;
    final completer = Completer<List<T>>();

    final latestStreamSubscription = _createSnapshotStream().listen((documents) {
      /// Add/update documents based on this new event.
      documents.forEach((doc) {
        final formattedDoc = doc.data()! as Map<String, dynamic>;
        final firestoreDoc = Document(doc.id, formattedDoc);
        final existingDocIndex = _allResults.indexWhere((item) => item.id == doc.id);

        if (existingDocIndex != -1) {
          _allResults[existingDocIndex] = firestoreDoc;
        } else {
          _allResults.add(firestoreDoc);
        }
      });

      final deserializedResults = _deserializeAllResults();
      _controller.add(deserializedResults);

      // Make sure that this is the first listen trigger for this call, as we have to ignore subsequent listeners.
      if (!completer.isCompleted) {
        // Update `_hasMorePages` when the returned documents 
        _hasMorePages = documents.length >= pageSize;

        // Updates our cursor with a new one if there was at least one document returned.
        if (documents.isNotEmpty) {
          _cursorRef = documents.last;
        }

        _isLoadingNextPage = false;
        completer.complete(deserializedResults);
      }
    },
    onError: (error) {
      _isLoadingNextPage = false;
      final wrapped = FirestoreDatabaseError('Failed to load more documents in query "${_query.parameters}"', error);

      if (!completer.isCompleted) {
        completer.completeError(wrapped);
      } else {
        throw wrapped;
      }
    });

    _streamSubscriptions.add(latestStreamSubscription);
    return completer.future;
  }

  @override
  List<T> getAllResults() => _deserializeAllResults();

  @override
  Future<void> dispose() async {
    // TODO(matuella): Test if I really need to manually close all subs or only the root `_controller`.
    await Future.wait(_streamSubscriptions.map((sub) => sub.cancel()));  
    await _controller.close();
  }

  /// Creates a [Stream] of [cf.QueryDocumentSnapshot] retrieved from [query].
  ///
  /// If [listen] is `true` the resulting stream emits when the queried documents are updated.
  Stream<List<cf.QueryDocumentSnapshot>> _createSnapshotStream() {
    // Limits the next fetch using the size of the page.
    var builtQuery = _query.limit(pageSize);

    // If the cursor reference is not null, we must use this cursor to begin the next query fetch.
    if (_cursorRef != null) {
      builtQuery = builtQuery.startAfterDocument(_cursorRef!);
    }

    // TODO(matuella): Test if this is leaking (meaning if it stops emitting events after the instance is disposed)
    final controller = StreamController<List<cf.QueryDocumentSnapshot>>();

    if (listenToChanges) {
      // ignore: unawaited_futures
      builtQuery
          .snapshots()
          .handleError(controller.addError)
          .forEach((snapshot) => controller.add(snapshot.docs))
          .catchError(controller.addError);
    } else {
      builtQuery.get().then((snapshot) => controller.add(snapshot.docs)).catchError(controller.addError);
    }

    return controller.stream;
  }

  List<T> _deserializeAllResults() => _allResults.map(deserialize).toList();
}
