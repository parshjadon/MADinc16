// This temporary test APK uses ignored private settings and must not be published.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:science_signal/attempt_store.dart';
import 'package:science_signal/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Private replacement configuration authenticates and verifies deployed records',
    (tester) async {
      final options = DefaultFirebaseOptions.currentPlatform;
      expect(options.apiKey, isNotEmpty);
      await Firebase.initializeApp(options: options);
      final auth = FirebaseAuth.instance;
      final db = FirebaseFirestore.instance;
      db.settings = const Settings(persistenceEnabled: false);
      await auth.signInWithEmailAndPassword(
        email: const String.fromEnvironment('TEST_EMAIL_A'),
        password: const String.fromEnvironment('TEST_PASSWORD_A'),
      );
      final uid = auth.currentUser!.uid;
      final store = FirestoreAttemptStore(db, auth);
      const originalId = String.fromEnvironment('TEST_RESTART_ID');
      final original = await store.read(uid, originalId);
      expect(original, isNotNull);
      expect(original!.correctCount, 2);
      final id = store.newId(uid);
      await store.commit(FrozenAttempt(uid, id, 2));
      final saved = await store.read(uid, id);
      expect(saved, isNotNull);
      expect(saved!.correctCount, 2);
      debugPrint(
        'SECURITY_VERIFICATION ${jsonEncode({'time': DateTime.now().toUtc().toIso8601String(), 'originalSuffix': originalId.substring(originalId.length - 6), 'newSuffix': id.substring(id.length - 6), 'result': 'Replacement private configuration authenticated user A, read original 2/5 record from server, committed and server-verified one new immutable 2/5 record.', 'status': 'PASS'})}',
      );
    },
  );
}
