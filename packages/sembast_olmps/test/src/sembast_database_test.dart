import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast_olmps/sembast_olmps.dart';

void main() {
  group('SembastDatabase', () {
    final fakeObject = {'fake': 'fake'};
    const fakeRecordId = 'a-fake-id';
    const fakeRawStore = 'fake_store';
    final fakeStore = stringMapStoreFactory.store(fakeRawStore);
    final fakeRecord = fakeStore.record(fakeRecordId);

    late Database memorySembast;
    late SembastDatabase db;

    setUp(() async {
      await databaseFactoryMemory.deleteDatabase('test.db');
      memorySembast = await databaseFactoryMemory.openDatabase('test.db');
      db = SembastDatabaseImpl(memorySembast);
    });

    group('SembastDatabaseImpl', () {
      test('should put a new object', () async {
        expect(await fakeRecord.get(memorySembast), isNull);

        await db.put(id: fakeRecordId, object: fakeObject, store: fakeRawStore);

        expect(await fakeRecord.get(memorySembast), fakeObject);
      });

      test('should put multiple objects at once', () async {
        expect(await fakeRecord.get(memorySembast), isNull);

        final records = [fakeRecordId, 'second-$fakeRecordId'];
        final fakeObjects = [fakeObject, fakeObject];
        await db.putAll(ids: records, objects: fakeObjects, store: fakeRawStore);

        expect(await fakeStore.records(records).get(memorySembast), fakeObjects);
      });

      test('should fail to put a different amount of objects and ids', () async {
        await expectLater(
          () async {
            await db.putAll(ids: ['a', 'b'], objects: [fakeObject], store: fakeRawStore);
          },
          throwsA(isA<AssertionError>()),
        );
      });

      test('should update an existing object', () async {
        await fakeRecord.put(memorySembast, fakeObject);

        final fakeUpdatedObject = {'fake': 'fakeUpdated', 'newFake': 'fake'};

        await db.put(id: fakeRecordId, object: fakeUpdatedObject, store: fakeRawStore);

        expect(await fakeRecord.get(memorySembast), fakeUpdatedObject);
      });

      test('should remove pre-existing fields in an update without merge', () async {
        await fakeRecord.put(memorySembast, fakeObject);

        final fakeUpdatedObject = {'newFake': 'fake'};

        await db.put(id: fakeRecordId, object: fakeUpdatedObject, store: fakeRawStore, shouldMerge: false);

        expect(await fakeRecord.get(memorySembast), fakeUpdatedObject);
      });

      test('should maintain pre-existing fields in an update with merge', () async {
        await fakeRecord.put(memorySembast, fakeObject);

        final fakeUpdatedObject = {'newFake': 'fake'};

        await db.put(id: fakeRecordId, object: fakeUpdatedObject, store: fakeRawStore);

        fakeUpdatedObject.addAll(fakeObject);
        expect(await fakeRecord.get(memorySembast), fakeUpdatedObject);
      });

      test('should remove an existing object', () async {
        await fakeRecord.put(memorySembast, fakeObject);

        expect(await fakeRecord.get(memorySembast), fakeObject);
        await db.remove(id: fakeRecordId, store: fakeRawStore);
        expect(await fakeRecord.get(memorySembast), isNull);

        expect(await fakeRecord.get(memorySembast), isNull);
      });

      test('should remove multiple existing objects at once', () async {
        final records = [fakeRecordId, 'second-$fakeRecordId'];
        final fakeObjects = [fakeObject, fakeObject];
        await fakeStore.records(records).put(memorySembast, fakeObjects);

        expect(await fakeStore.records(records).get(memorySembast), fakeObjects);
        await db.removeAll(ids: records, store: fakeRawStore);

        expect(await fakeStore.find(memorySembast), const <dynamic>[]);
      });

      test('should do nothing when removing a nonexistent object', () async {
        await fakeRecord.put(memorySembast, fakeObject);

        await db.remove(id: fakeRecordId, store: fakeRawStore);
        expect(await fakeRecord.get(memorySembast), isNull);
      });

      test('should retrieve a single existing object', () async {
        await fakeRecord.put(memorySembast, fakeObject);

        final object = await db.get(id: fakeRecordId, store: fakeRawStore);
        expect(object, isNotNull);
      });

      test('should retrieve multiple existing objects by their ids', () async {
        final records = [fakeRecordId, 'second-$fakeRecordId'];
        final fakeObjects = [fakeObject, fakeObject];
        await fakeStore.records(records).put(memorySembast, fakeObjects);

        final objects = await db.getAllByIds(ids: records, store: fakeRawStore);
        expect(objects, fakeObjects);
      });

      test('should get null when retrieving a single nonexistent object', () async {
        final object = await db.get(id: fakeRecordId, store: fakeRawStore);
        expect(object, isNull);
      });

      test('should retrieve multiple objects', () async {
        await fakeRecord.put(memorySembast, fakeObject);
        await stringMapStoreFactory.store(fakeRawStore).record('2').put(memorySembast, fakeObject);

        final objects = await db.getAll(store: fakeRawStore);
        expect(objects.length, 2);
      });

      test('should retrieve an empty list if there is no objects in the store', () async {
        final objects = await db.getAll(store: fakeRawStore);
        expect(objects.isEmpty, true);
      });

      test('should emit new events when listening to store updates', () async {
        final stream = await db.listenAll(store: fakeRawStore);

        final expectedEmissions = <List<Map<String, String>>>[
          [], // First emission is the "onListen", which is an empty store
          [fakeObject],
          List.generate(2, (_) => fakeObject),
        ];

        expect(stream, emitsInOrder(expectedEmissions));

        await fakeRecord.put(memorySembast, fakeObject);
        await stringMapStoreFactory.store(fakeRawStore).record('other-fake-id').put(memorySembast, fakeObject);
      });

      test('should emit new events when listening to a single object', () async {
        final stream = await db.listenTo(id: fakeRecordId, store: fakeRawStore);

        final updatedFakeObject = {'fake': 'updated'};

        final expectedEmissions = <Map<String, dynamic>?>[
          null, // First emission is the "onListen", which is an empty store
          fakeObject,
          updatedFakeObject,
          null,
        ];

        expect(stream, emitsInOrder(expectedEmissions));

        await fakeRecord.put(memorySembast, fakeObject);
        await fakeRecord.put(memorySembast, updatedFakeObject);
        await fakeRecord.delete(memorySembast);
      });

      test('should throw when operating on a closed database', () async {
        await db.close();

        await expectLater(
          () async {
            await db.get(id: 'id', store: 'store');
          },
          throwsA(isA<Exception>()),
        );
      });
    });
    group('SembastTransactionHandler', () {
      test('should not make any updates in a failed transaction', () async {
        await fakeRecord.put(memorySembast, fakeObject);

        try {
          await db.runInTransaction(() async {
            const generatedRecords = 10;
            final fakeRecordsIds = List.generate(generatedRecords, (index) => '$fakeRecordId-$index');
            await db.putAll(
              ids: fakeRecordsIds,
              objects: fakeRecordsIds.map((_) => fakeObject).toList(),
              store: fakeRawStore,
            );
            final updatedAddedRecords = await db.getAll(store: fakeRawStore);
            expect(updatedAddedRecords.length, generatedRecords + 1);

            await db.remove(id: fakeRecordId, store: fakeRawStore);
            final updatedRemovedRecord = await db.getAll(store: fakeRawStore);
            expect(updatedRemovedRecord.length, generatedRecords);

            throw Error();
          });
          // ignore: avoid_catches_without_on_clauses, empty_catches
        } catch (error) {}

        final records = await db.getAll(store: fakeRawStore);
        expect(records.length, 1);
      });

      test('should correctly store multiple updates in a transaction', () async {
        const secondRecordId = 'second-$fakeRecordId';
        await Future.wait([
          fakeRecord.put(memorySembast, fakeObject),
          fakeStore.record(secondRecordId).put(memorySembast, fakeObject),
        ]);

        await db.runInTransaction(() async {
          await db.remove(id: fakeRecordId, store: fakeRawStore);
          await db.remove(id: secondRecordId, store: fakeRawStore);
        });

        expect(await db.getAll(store: fakeRawStore), isEmpty);
      });

      test('should throw an error if multiple transactions are created simultaneously', () async {
        await expectLater(
          () async {
            await Future.wait([
              db.runInTransaction(() async {
                await Future.delayed(const Duration(seconds: 1), () {});
              }),
              db.runInTransaction(() async {
                await Future.delayed(const Duration(seconds: 1), () {});
              }),
            ]);
          },
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('should throw an error if transaction throw', () async {
        await expectLater(
          () async {
            await db.runInTransaction(() => throw 'anything');
          },
          throwsA(isA<TransactionError>()),
        );
      });
    });
  });

  group('openDatabase', () {
    const fakePathProvider = '.';
    const fakeName = 'fake';
    const fakeFirstVersion = 10;
    const fakePath = '$fakePathProvider/$fakeName';

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // TODO(matuella): not sure why need to all platforms channels, maybe because `path_provider` changed its plugin structure?
      ['android', 'ios', 'linux', 'macos', 'windows'].forEach((platform) {
        MethodChannel('plugins.flutter.io/path_provider_$platform')
            .setMockMethodCallHandler((_) async => fakePathProvider);
      });
    });

    setUp(() async {
      await databaseFactoryMemory.deleteDatabase(fakePath);
    });

    test('should call onDatabaseCreation on the first database open', () async {
      var hasCalledCreateCallback = false;
      await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeFirstVersion,
        onDatabaseCreation: (db, version) async {
          expect(version, fakeFirstVersion);
          expect(db.path, fakePath);
          hasCalledCreateCallback = true;
        },
        onVersionChanged: (_, __, ___) => fail('called `onVersionChanged`'),
        factory: databaseFactoryMemory,
      );

      expect(hasCalledCreateCallback, isTrue, reason: 'Must call `onDatabaseCreation`');
    });

    test('should call onVersionChanged when upgrading the schema', () async {
      final fakeNewVersion = 11;
      final db = await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeFirstVersion,
        factory: databaseFactoryMemory,
      );

      await db.close();

      var hasCalledVersionCallback = false;
      await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeNewVersion,
        onDatabaseCreation: (_, __) => fail('called `onDatabaseCreation`'),
        onVersionChanged: (db, oldVersion, newVersion) async {
          expect(oldVersion, fakeFirstVersion);
          expect(newVersion, fakeNewVersion);
          expect(db.path, fakePath);

          hasCalledVersionCallback = true;
        },
        factory: databaseFactoryMemory,
      );

      expect(hasCalledVersionCallback, isTrue, reason: 'Must call `onVersionChanged`');
    });

    test('should run changes when upgrading the schema', () async {
      final fakeNewVersion = 11;
      final db = await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeFirstVersion,
        factory: databaseFactoryMemory,
      );

      await db.put(id: 'fake', object: {'fake': 'fake'}, store: '');
      await db.close();

      final migratedDb = await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeNewVersion,
        onDatabaseCreation: (_, __) => fail('called `onDatabaseCreation`'),
        onVersionChanged: (db, _, __) async {
          final fakeStore = stringMapStoreFactory.store('');
          final records = await fakeStore.count(db);
          expect(records, 1);

          await fakeStore.delete(db);
        },
        factory: databaseFactoryMemory,
      );

      final records = await migratedDb.getAll(store: '');
      expect(records.length, 0);
    });

    test('should ignore callbacks when opening the database with the same last schema', () async {
      final db = await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeFirstVersion,
        factory: databaseFactoryMemory,
      );

      await db.close();

      await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeFirstVersion,
        onDatabaseCreation: (_, __) => fail('called `onDatabaseCreation`'),
        onVersionChanged: (_, __, ___) => fail('called `onVersionChanged`'),
        factory: databaseFactoryMemory,
      );
    });

    test('should allow multiple references to the same database', () async {
      final db1 = await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeFirstVersion,
        factory: databaseFactoryMemory,
      );

      await db1.put(id: 'fake', object: {}, store: '');

      final db2 = await openDatabase(
        dbName: fakeName,
        schemaVersion: fakeFirstVersion,
        factory: databaseFactoryMemory,
      );

      final db1Result = await db1.get(id: 'fake', store: '');

      expect(db1Result, isNotNull);
      expect(db1Result, await db2.get(id: 'fake', store: ''));
    });

    test('should throw when using a non-positive integer schema version', () async {
      await expectLater(
        () async {
          await openDatabase(
            schemaVersion: 0,
            factory: databaseFactoryMemory,
          );
        },
        throwsA(isA<AssertionError>()),
      );

      await expectLater(
        () async {
          await openDatabase(
            schemaVersion: -1,
            factory: databaseFactoryMemory,
          );
        },
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
