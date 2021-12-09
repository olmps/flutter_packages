import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firestore_olmps/firestore_olmps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// firebase --project=fake emulators:start --export-on-exit ./exports/
// firebase --project=fake emulators:start --import=./exports/
//
// flutter drive --driver=test_driver/integration_test.dart --target=integration_test/whatev_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late FirebaseFirestore inst;
  setUpAll(() async {
    await Firebase.initializeApp(
        options: const FirebaseOptions(
      appId: '1:79601577497:ios:5f2bcc6ba8cecddd',
      messagingSenderId: '79601577497',
      apiKey: 'AIzaSyArgmRGfB5kiQT6CunAOmKRVKEsxKmy6YI-G72PVU',
      projectId: 'fake',
    ));

    inst = FirebaseFirestore.instance..useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('firestore database a', (z) async {
    final db = FirestoreDatabase(inst);
    expect((await db.getAll(collectionPath: 'test')).length, 2);
  });

  testWidgets('firestore database b', (z) async {
    final db = FirestoreDatabase(inst);
    expect((await db.getAll(collectionPath: 'test', filters: [QueryFilter(field: 'a', isEqualTo: 'b')])).length, 1);
    expect((await db.getAll(collectionPath: 'test', filters: [QueryFilter(field: 'a', isEqualTo: 'c')])).length, 1);
  });
}
