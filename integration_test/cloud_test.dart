// All Firestore operations in this suite target the DEPLOYED project.
// Credentials are supplied with --dart-define-from-file=private/test_accounts.json.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:science_signal/attempt_store.dart';
import 'package:science_signal/firebase_options.dart';
import 'package:science_signal/main.dart';
import 'package:science_signal/quiz.dart';
import 'package:science_signal/round_controller.dart';

const emailA = String.fromEnvironment('TEST_EMAIL_A');
const passwordA = String.fromEnvironment('TEST_PASSWORD_A');
const emailB = String.fromEnvironment('TEST_EMAIL_B');
const passwordB = String.fromEnvironment('TEST_PASSWORD_B');
const appCommit = String.fromEnvironment(
  'APP_COMMIT',
  defaultValue: 'working-tree',
);

void record(String id, String actual, {String? roundId}) {
  final suffix = roundId == null
      ? 'none'
      : roundId.substring(roundId.length - 6);
  // Never output passwords, emails, auth tokens, or full document IDs.
  debugPrint(
    'EVIDENCE ${jsonEncode({'id': id, 'time': DateTime.now().toUtc().toIso8601String(), 'commit': appCommit, 'roundSuffix': suffix, 'actual': actual, 'status': 'PASS'})}',
  );
}

class LoadedQuestions implements QuestionSource {
  LoadedQuestions(this.items);
  final List<ScienceQuestion> items;
  @override
  Duration get retryAfter => Duration.zero;
  @override
  Future<List<ScienceQuestion>> load() async => items;
}

Future<RoundController> finishRound(
  String uid,
  AttemptStore store,
  List<ScienceQuestion> items, {
  int correct = 2,
}) async {
  final round = RoundController(LoadedQuestions(items), store)
    ..identityChanged(uid);
  await round.startRound();
  for (var i = 0; i < 5; i++) {
    final answer = i < correct ? items[i].correct : !items[i].correct;
    round.choose(answer);
    round.choose(!answer);
    round.advance();
  }
  expect(round.score, correct);
  return round;
}

/// Delays delivery of an ACTUAL server read, never replaces its contents.
class DelayedServerRead implements AttemptStore {
  DelayedServerRead(this.real);
  final AttemptStore real;
  final received = Completer<ServerAttempt?>();
  final release = Completer<void>();
  @override
  String newId(String uid) => real.newId(uid);
  @override
  Future<void> commit(FrozenAttempt a) => real.commit(a);
  @override
  Future<ServerAttempt?> read(String uid, String id) async {
    final actual = await real.read(uid, id);
    received.complete(actual);
    await release.future;
    return actual;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Deployed Class B contract T01-T12 and graduate concurrency', (
    tester,
  ) async {
    expect(
      emailA.isNotEmpty &&
          passwordA.isNotEmpty &&
          emailB.isNotEmpty &&
          passwordB.isNotEmpty,
      isTrue,
      reason:
          'Supply private/test_accounts.json through --dart-define-from-file.',
    );
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    db.settings = const Settings(persistenceEnabled: false);
    await auth.signOut();

    // T01 exercises the real sign-in screen and visible Firebase error.
    await tester.pumpWidget(const ScienceSignalApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), emailA);
    await tester.enterText(
      find.byKey(const Key('password')),
      'deliberately-incorrect-password',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.ensureVisible(find.byKey(const Key('signIn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signIn')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 30 && find.byKey(const Key('authError')).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      }
    });
    expect(find.byKey(const Key('authError')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('email')), '');
    await tester.enterText(find.byKey(const Key('password')), '');
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('T01-auth-error');
    await tester.enterText(find.byKey(const Key('email')), emailA);
    await tester.enterText(find.byKey(const Key('password')), passwordA);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.ensureVisible(find.byKey(const Key('signIn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signIn')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var i = 0; i < 30 && auth.currentUser == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      }
    });
    final uidA = auth.currentUser!.uid;
    expect(find.byKey(const Key('identity')), findsOneWidget);
    record(
      'T01',
      'Invalid login displayed an error; valid login authenticated intended test user A.',
    );

    final source = OpenTriviaSource();
    final questions = await source.load();
    expect(questions, hasLength(5));
    binding.reportData = {
      'encoded': questions.first.encodedPrompt,
      'decoded': questions.first.prompt,
    };
    record(
      'T02',
      'Exact URL returned 5 validated questions. Encoded: ${questions.first.encodedPrompt}; decoded: ${questions.first.prompt}',
    );
    final repo = FirestoreAttemptStore(db, auth);
    final playing = RoundController(LoadedQuestions(questions), repo)
      ..identityChanged(uidA);
    await playing.startRound();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ScienceSignalApp(controller: playing));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('answerTrue'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('answerFalse'))).dx),
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('continue'))).onPressed,
      isNull,
    );
    for (var i = 0; i < 5; i++) {
      final answer = i < 2 ? questions[i].correct : !questions[i].correct;
      final button = find.byKey(Key(answer ? 'answerTrue' : 'answerFalse'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      expect(find.byKey(const Key('answerFeedback')), findsOneWidget);
      if (i == 0) await binding.takeScreenshot('T04-fixed-choices-feedback');
      await tester.ensureVisible(find.byKey(const Key('continue')));
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();
    }
    expect(playing.phase, RoundPhase.readyToSubmit);
    expect(playing.score, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    final round = await finishRound(uidA, repo, questions);
    expect(round.selections, hasLength(5));
    record(
      'T04',
      'Actual UI: True precedes False, Continue locked until selection, text/icon/color feedback, choices disabled after answer; five review entries and repeated selection guard produced 2/5.',
      roundId: round.roundId,
    );
    final id = round.roundId!;
    await Future.wait([round.submit(), round.submit()]);
    expect(round.phase, RoundPhase.cloudVerified);
    expect(round.verified!.correctCount, 2);
    final original = await repo
        .reference(uidA, id)
        .get(const GetOptions(source: Source.server));
    expect(original.data()!.keys, hasLength(6));
    expect(original.data()!['submittedAt'], isA<Timestamp>());
    expect(original.metadata.hasPendingWrites, isFalse);
    expect(original.metadata.isFromCache, isFalse);
    record(
      'T06',
      'Double Submit produced one exact document with six fields, resolved timestamp and server-only confirmation.',
      roundId: id,
    );
    // This ID is returned to the driver privately for the genuine restart test.
    binding.reportData!['restartId'] = id;
    binding.reportData!['serverProof'] = {
      'projectId': db.app.options.projectId,
      'database': '(default)',
      'uidSuffix': uidA.substring(uidA.length - 6),
      'roundSuffix': id.substring(id.length - 6),
      'schemaVersion': original.data()!['schemaVersion'],
      'variant': original.data()!['variant'],
      'categoryId': original.data()!['categoryId'],
      'questionCount': original.data()!['questionCount'],
      'correctCount': original.data()!['correctCount'],
      'submittedAt': (original.data()!['submittedAt'] as Timestamp)
          .toDate()
          .toUtc()
          .toIso8601String(),
      'source': 'server',
      'isFromCache': original.metadata.isFromCache,
      'hasPendingWrites': original.metadata.hasPendingWrites,
    };

    await round.startRound();
    expect(round.roundId, isNot(id));
    expect(round.score, 0);
    expect(round.selections, everyElement(isNull));
    record(
      'T05',
      'All 5 answers reviewed; replay allocated a new ID and reset every selection.',
      roundId: round.roundId,
    );

    final denied = await finishRound(uidA, repo, questions, correct: 3);
    repo.injectAfterNextCommit(VerificationFault.permissionDenied);
    await denied.submit();
    expect(denied.writeAcknowledged, isTrue);
    expect(denied.phase, RoundPhase.permissionDenied);
    expect(
      denied.message,
      contains('Write acknowledged; verification unavailable.'),
    );
    expect(denied.canReplay, isFalse);
    expect(denied.canSignOut, isFalse);
    final deniedId = denied.roundId!;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ScienceSignalApp(controller: denied));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cloudMessage')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('T09-acknowledged-verification-denied');
    await denied.retryVerification();
    expect(denied.phase, RoundPhase.cloudVerified);
    expect(denied.roundId, deniedId);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('serverProof')));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('T09-server-verified');
    record(
      'T09',
      'REAL transaction acknowledged; labelled injected permission-denied read; retry verified the same REAL server record (3/5). No second document.',
      roundId: deniedId,
    );

    final offline = await finishRound(uidA, repo, questions, correct: 1);
    final offlineId = offline.roundId;
    await db.disableNetwork();
    await offline.submit();
    expect(offline.phase, isNot(RoundPhase.cloudVerified));
    expect(offline.roundId, offlineId);
    expect(offline.canReplay, isFalse);
    await db.enableNetwork();
    // A 10-second UI timeout cannot cancel the original SDK transaction.
    for (var i = 0; i < 200 && offline.operationActive; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(offline.operationActive, isFalse);
    await offline.retryVerification();
    if (offline.phase == RoundPhase.readyToSubmit) await offline.submit();
    expect(offline.phase, RoundPhase.cloudVerified);
    expect(offline.roundId, offlineId);
    record(
      'T08',
      'Network disabled before transaction; no false success. Reconnected, waited for original operation, reconciled original ID and recovered.',
      roundId: offlineId,
    );

    for (final fault in [
      VerificationFault.unavailable,
      VerificationFault.resourceExhausted,
    ]) {
      final failed = await finishRound(uidA, repo, questions);
      repo.injectAfterNextCommit(fault);
      await failed.submit();
      expect(failed.phase, RoundPhase.verificationUnavailable);
      expect(failed.writeAcknowledged, isTrue);
      expect(
        failed.errorCode,
        fault == VerificationFault.unavailable
            ? 'unavailable'
            : 'resource-exhausted',
      );
      expect(failed.message, contains('[DEVELOPMENT INJECTION]'));
      await failed.retryVerification();
      expect(failed.phase, RoundPhase.cloudVerified);
      record(
        'T12',
        'Labelled ${fault.name} injection had distinct message and one manual server-read retry; real commit and final read.',
        roundId: failed.roundId,
      );
    }

    final appB = await Firebase.initializeApp(
      name: 'client-B',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final authB = FirebaseAuth.instanceFor(app: appB);
    final dbB = FirebaseFirestore.instanceFor(app: appB);
    dbB.settings = const Settings(persistenceEnabled: false);
    await authB.signInWithEmailAndPassword(email: emailB, password: passwordB);
    final pathAFromB = dbB.collection('users').doc(uidA).collection('attempts');
    Future<void> expectDenied(Future<Object?> operation) => expectLater(
      operation,
      throwsA(
        isA<FirebaseException>().having(
          (e) => e.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    await expectDenied(
      pathAFromB.doc(id).get(const GetOptions(source: Source.server)),
    );
    await expectDenied(
      pathAFromB.doc().set({
        ...const FrozenAttempt('', '', 1).fixedFields,
        'submittedAt': FieldValue.serverTimestamp(),
      }),
    );
    record(
      'T10',
      'Separate signed-in user B client was denied BOTH read and create under user A path by deployed rules.',
      roundId: id,
    );

    final ownerAttempts = repo.reference(uidA, id).parent;
    await expectDenied(
      ownerAttempts.doc().set({
        ...const FrozenAttempt('', '', 6).fixedFields,
        'submittedAt': FieldValue.serverTimestamp(),
      }),
    );
    await expectDenied(
      ownerAttempts.doc().set({
        ...const FrozenAttempt('', '', 2).fixedFields,
        'submittedAt': FieldValue.serverTimestamp(),
        'extra': true,
      }),
    );
    await expectDenied(repo.reference(uidA, id).update({'correctCount': 4}));
    final unchanged = await repo.read(uidA, id);
    expect(unchanged!.correctCount, 2);
    expect(
      unchanged.submittedAt,
      round.verified?.submittedAt ?? original.data()!['submittedAt'].toDate(),
    );
    record(
      'T11',
      'Deployed rules rejected score 6, an extra field, and update; original score and timestamp unchanged.',
      roundId: id,
    );

    // Two independent Firebase clients, same authenticated test user.
    await authB.signOut();
    await authB.signInWithEmailAndPassword(email: emailA, password: passwordA);
    final repoB = FirestoreAttemptStore(dbB, authB);
    final conflictId = repo.newId(uidA);
    Future<String> compete(AttemptStore client, int score) async {
      try {
        await client.commit(FrozenAttempt(uidA, conflictId, score));
        return 'won:$score';
      } on CloudProblem catch (e) {
        expect(e.code, 'collision');
        return 'collision:$score';
      }
    }

    final outcomes = await Future.wait([compete(repo, 1), compete(repoB, 4)]);
    expect(outcomes.where((x) => x.startsWith('won:')), hasLength(1));
    expect(outcomes.where((x) => x.startsWith('collision:')), hasLength(1));
    final winner = await repo.read(uidA, conflictId);
    expect(outcomes, contains('won:${winner!.correctCount}'));
    record(
      'G01',
      'Two clients concurrently submitted 1 and 4 at same ID: ${outcomes.join(', ')}; server winner ${winner.correctCount}/5.',
      roundId: conflictId,
    );

    final id1 = repo.newId(uidA);
    final id2 = repoB.newId(uidA);
    await Future.wait([
      repo.commit(FrozenAttempt(uidA, id1, 0)),
      repoB.commit(FrozenAttempt(uidA, id2, 5)),
    ]);
    final isolated = await Future.wait([
      repo.read(uidA, id1),
      repoB.read(uidA, id2),
    ]);
    expect(isolated[0]!.roundId, id1);
    expect(isolated[0]!.correctCount, 0);
    expect(isolated[1]!.roundId, id2);
    expect(isolated[1]!.correctCount, 5);
    record(
      'G02',
      'Concurrent independent clients returned their own exact IDs and scores: …${id1.substring(id1.length - 6)}=0; …${id2.substring(id2.length - 6)}=5.',
      roundId: id2,
    );

    final delayed = DelayedServerRead(repo);
    final stale = await finishRound(uidA, delayed, questions);
    final pending = stale.submit();
    await delayed.received.future;
    await auth.signOut();
    await auth.signInWithEmailAndPassword(email: emailB, password: passwordB);
    stale.identityChanged(auth.currentUser!.uid);
    delayed.release.complete();
    await pending;
    expect(stale.uid, auth.currentUser!.uid);
    expect(stale.phase, RoundPhase.idle);
    expect(stale.verified, isNull);
    expect(stale.roundId, isNull);
    expect(stale.writeAcknowledged, isFalse);
    record(
      'G03',
      'Delayed delivery of actual user A server response after real sign-in as user B was discarded by generation/UID/ID guards.',
    );
    await auth.signOut();
    await auth.signInWithEmailAndPassword(email: emailA, password: passwordA);
    binding.reportData!['verifiedSuffix'] = id.substring(id.length - 6);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
