import 'dart:async';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:sembast/sembast.dart' as sembast;
import 'package:sembast/sembast_io.dart' as sembast_io;

import 'transaction_error.dart';

export 'package:sembast/sembast.dart'
    show
        Database,
        DatabaseFactory,
        Finder,
        Filter,
        SembastRecordRefExtension,
        SembastRecordsRefExtension,
        SembastStoreRefExtension,
        stringMapStoreFactory;
export 'package:sembast/sembast_io.dart';
export 'package:sembast/sembast_memory.dart';

/// Sembast implementation for an atomic database transaction.
///
/// Currently, there is no support for multiple transactions running simultaneously. If necessary, run a transaction
/// once, then run another after completing the first one.
///
/// Throws a [UnsupportedError] if multiple transactions are ran in parallel.
/// 
/// Throws a [TransactionError] if anything is thrown while running the transaction callback.
abstract class SembastTransactionHandler {
  SembastTransactionHandler(this.db);

  @protected
  final sembast.Database db;

  @protected
  sembast.Transaction? currentTransaction;

  Future<void> runInTransaction(Future<void> Function() run) async {
    if (currentTransaction != null) {
      throw UnsupportedError('Trying to run a new transaction while there is one already running');
    }

    try {
      await db.transaction((transaction) async {
        currentTransaction = transaction;
        await run();
      });
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      // Not able to keep stack-trace while wrapping in a new error. https://github.com/dart-lang/sdk/issues/10297
      throw TransactionError('Failed transaction with Error:\n${error.toString()} \nStackTrace:\n${stack.toString()}');
    } finally {
      currentTransaction = null;
    }
  }
}

/// Handles the local persistence to the database.
///
/// To properly get a database instance, call [openDatabase].
abstract class SembastDatabase extends SembastTransactionHandler {
  SembastDatabase(sembast.Database db) : super(db);

  /// Adds an [object] to the [store], using an [id].
  ///
  /// If there is already an object with the same [id], the default behavior is to merge all of its fields.
  ///
  /// [shouldMerge] should be `false` if pre-existing fields should not be merged.
  Future<void> put({
    required String id,
    required Map<String, dynamic> object,
    required String store,
    bool shouldMerge = true,
  });

  /// Adds a list of [objects] to the [store], using their respective [ids].
  ///
  /// If there is already one or more objects with the same [ids], defaults to merging all of its fields.
  ///
  /// [shouldMerge] should be `false` if pre-existing fields should not be merged.
  Future<void> putAll({
    required List<String> ids,
    required List<Map<String, dynamic>> objects,
    required String store,
    bool shouldMerge = true,
  });

  /// Deletes the value with [id] from the [store].
  Future<void> remove({required String id, required String store});

  /// Deletes all objects with the following [ids] from the [store].
  Future<void> removeAll({required List<String> ids, required String store});

  /// Retrieves an object with [id] from the [store].
  ///
  /// Returns `null` if the key doesn't exist.
  Future<Map<String, dynamic>?> get({required String id, required String store});

  /// Retrieves all objects within [store].
  Future<List<Map<String, dynamic>>> getAll({required String store, sembast.Finder? finder});

  /// Retrieves all objects with the following [ids] from the [store].
  Future<List<Map<String, dynamic>?>> getAllByIds({required List<String> ids, required String store});

  /// Retrieves a stream of all the [store] objects, triggered whenever any update occurs to this [store].
  Future<Stream<List<Map<String, dynamic>>>> listenAll({required String store});

  /// Retrieves a stream of a single [store] object, triggered whenever any update occurs to this object's [id].
  Future<Stream<Map<String, dynamic>?>> listenTo({required String id, required String store});

  /// Close this database, preventing any further operations with this instance.
  Future<void> close();
}

@visibleForTesting
class SembastDatabaseImpl extends SembastDatabase {
  SembastDatabaseImpl(sembast.Database db) : super(db);

  @override
  Future<void> put({
    required String id,
    required Map<String, dynamic> object,
    required String store,
    bool shouldMerge = true,
  }) async {
    final storeMap = sembast.stringMapStoreFactory.store(store);
    await storeMap.record(id).put(currentTransaction ?? db, object, merge: shouldMerge);
  }

  @override
  Future<void> putAll({
    required List<String> ids,
    required List<Map<String, dynamic>> objects,
    required String store,
    bool shouldMerge = true,
  }) async {
    assert(ids.length == objects.length, 'All `objects` must have the same length as `ids`');

    final storeMap = sembast.stringMapStoreFactory.store(store);
    await storeMap.records(ids).put(currentTransaction ?? db, objects, merge: shouldMerge);
  }

  @override
  Future<void> remove({required String id, required String store}) async {
    final storeMap = sembast.stringMapStoreFactory.store(store);
    await storeMap.record(id).delete(currentTransaction ?? db);
  }

  @override
  Future<void> removeAll({required List<String> ids, required String store}) async {
    final storeMap = sembast.stringMapStoreFactory.store(store);
    await storeMap.records(ids).delete(currentTransaction ?? db);
  }

  @override
  Future<Map<String, dynamic>?> get({required String id, required String store}) {
    final storeMap = sembast.stringMapStoreFactory.store(store);
    return storeMap.record(id).get(currentTransaction ?? db);
  }

  @override
  Future<List<Map<String, dynamic>>> getAll({required String store, sembast.Finder? finder}) async {
    final storeMap = sembast.stringMapStoreFactory.store(store);

    final allRecords = await storeMap.find(currentTransaction ?? db, finder: finder);
    return allRecords.map((record) => record.value).toList();
  }

  @override
  Future<List<Map<String, dynamic>?>> getAllByIds({required List<String> ids, required String store}) {
    final storeMap = sembast.stringMapStoreFactory.store(store);
    return storeMap.records(ids).get(currentTransaction ?? db);
  }

  @override
  Future<Stream<List<Map<String, dynamic>>>> listenAll({required String store}) async {
    final storeMap = sembast.stringMapStoreFactory.store(store);
    // Maps a list of `sembast` snapshot records into a list of objects.
    return storeMap.query().onSnapshots(db).map((snapshots) => snapshots.map((record) => record.value).toList());
  }

  @override
  Future<Stream<Map<String, dynamic>?>> listenTo({required String id, required String store}) async {
    final storeMap = sembast.stringMapStoreFactory.store(store);
    // Maps a single `sembast` snapshot record into an object.
    return storeMap.record(id).onSnapshot(db).map((snapshot) => snapshot?.value);
  }

  @override
  Future<void> close() => db.close();
}

typedef OnVersionChanged = Future<void> Function(sembast.Database db, int oldVersion, int newVersion);
typedef OnDatabaseCreation = Future<void> Function(sembast.Database db, int version);

/// Opens this application's [SembastDatabase], creating a new one if nonexistent.
///
/// [dbName] represents the file name in the respective application document's directory. Defaults to `sembast.db`.
///
/// [schemaVersion] defines the current database version. Must be a positive integer. Defaults to `1`.
///
/// Optional [onDatabaseCreation] and [onVersionChanged] can be provided to detect the respective callbacks, depending
/// on the database state. [onDatabaseCreation] will be called when this is the first time that this database has been
/// opened and [onVersionChanged] when [schemaVersion] is different from the last database-opening. [onVersionChanged]
/// won't be called when [onDatabaseCreation] is called.
///
/// Can override the default sembast factory ([sembast_io.databaseFactoryIo] is being used) by providing a [factory].
Future<SembastDatabase> openDatabase({
  String dbName = 'sembast.db',
  int schemaVersion = 1,
  OnDatabaseCreation? onDatabaseCreation,
  OnVersionChanged? onVersionChanged,
  sembast.DatabaseFactory? factory,
}) async {
  assert(schemaVersion >= 1, '`schemaVersion` be a positive integer');

  final dir = await path_provider.getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  final dbPath = path.join(dir.path, dbName);

  final baseFactory = factory ?? sembast_io.databaseFactoryIo;
  final db = await baseFactory.openDatabase(
    dbPath,
    version: schemaVersion,
    onVersionChanged: (db, oldVersion, newVersion) {
      // `oldVersion` is zero when running for the first time.
      if (oldVersion == 0) {
        onDatabaseCreation?.call(db, newVersion);
        return;
      }

      onVersionChanged?.call(db, oldVersion, newVersion);
    },
  );

  return SembastDatabaseImpl(db);
}
