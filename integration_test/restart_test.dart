import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:science_signal/firebase_options.dart';
import 'package:science_signal/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'T07 new Android process retrieves prior round without quiz or write',
    (tester) async {
      const id = String.fromEnvironment('TEST_RESTART_ID');
      expect(id, isNotEmpty);
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final auth = FirebaseAuth.instance;
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      await auth.signInWithEmailAndPassword(
        email: const String.fromEnvironment('TEST_EMAIL_A'),
        password: const String.fromEnvironment('TEST_PASSWORD_A'),
      );
      await tester.pumpWidget(const ScienceSignalApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retrieve a previous result'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('retrieveId')), id);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.byKey(const Key('retrieve')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('retrieve')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 100 && find.byKey(const Key('serverProof')).evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      expect(find.byKey(const Key('serverProof')), findsOneWidget);
      expect(find.byKey(const Key('questionPrompt')), findsNothing);
      expect(find.byKey(const Key('score')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('serverProof'))).data,
        contains('Server score: 2/5'),
      );
      await tester.ensureVisible(find.byKey(const Key('serverProof')));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('T07-restarted-server-retrieval');
      debugPrint(
        'EVIDENCE ${jsonEncode({'id': 'T07', 'time': DateTime.now().toUtc().toIso8601String(), 'commit': const String.fromEnvironment('APP_COMMIT'), 'roundSuffix': id.substring(id.length - 6), 'actual': 'Prior process force-stopped; fresh Android process signed in as same A and retrieved original 2/5 using actual app Source.server path, without quiz or write.', 'status': 'PASS'})}',
      );
    },
  );
}
