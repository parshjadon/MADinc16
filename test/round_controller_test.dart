import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:science_signal/attempt_store.dart';
import 'package:science_signal/quiz.dart';
import 'package:science_signal/round_controller.dart';

class Questions implements QuestionSource {
  @override
  Duration get retryAfter => Duration.zero;
  @override
  Future<List<ScienceQuestion>> load() async => List.generate(
    5,
    (i) => ScienceQuestion(
      prompt: 'Question $i',
      correct: i < 2,
      encodedPrompt: 'Question%20$i',
    ),
  );
}

/// Unit-test double ONLY. Live tests use FirestoreAttemptStore against deployed Firebase.
class MemoryTestStore implements AttemptStore {
  int allocated = 0;
  int commits = 0;
  int reads = 0;
  final records = <String, ServerAttempt>{};
  Object? readFault;
  Object? commitFault;
  Completer<void>? commitGate;
  Completer<ServerAttempt?>? readGate;
  @override
  String newId(String uid) => 'test-round-${++allocated}';
  @override
  Future<void> commit(FrozenAttempt a) async {
    commits++;
    if (commitGate != null) await commitGate!.future;
    if (commitFault != null) throw commitFault!;
    final existing = records['${a.uid}/${a.roundId}'];
    if (existing != null && existing.correctCount != a.correctCount) {
      throw const CloudProblem('collision', 'different payload');
    }
    records.putIfAbsent(
      '${a.uid}/${a.roundId}',
      () => ServerAttempt(
        a.uid,
        a.roundId,
        a.correctCount,
        DateTime.utc(2026, 11, 17),
      ),
    );
  }

  @override
  Future<ServerAttempt?> read(String uid, String id) async {
    reads++;
    if (readGate != null) return readGate!.future;
    if (readFault != null) {
      final fault = readFault!;
      readFault = null;
      throw fault;
    }
    return records['$uid/$id'];
  }
}

Future<RoundController> completed(
  MemoryTestStore store, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final round = RoundController(Questions(), store, uiTimeout: timeout);
  round.identityChanged('user-A');
  await round.startRound();
  for (var i = 0; i < 5; i++) {
    round.choose(true);
    round.advance();
  }
  return round;
}

void main() {
  test(
    'retrieving a different historical ID clears the previous round review',
    () async {
      final store = MemoryTestStore();
      final round = await completed(store);
      await round.submit();
      store.records['user-A/historical-id'] = ServerAttempt(
        'user-A',
        'historical-id',
        5,
        DateTime.utc(2026),
      );
      await round.retrieve('historical-id');
      expect(round.phase, RoundPhase.cloudVerified);
      expect(round.verified!.correctCount, 5);
      expect(
        round.questions,
        isEmpty,
        reason:
            'Old questions must never be attached to a different cloud result.',
      );
      expect(round.selections, isEmpty);
    },
  );
  test('T04 selection guard and repeated taps keep score at 2/5', () async {
    final store = MemoryTestStore();
    final round = RoundController(Questions(), store);
    round.identityChanged('user-A');
    await round.startRound();
    round.advance();
    expect(round.index, 0);
    for (var i = 0; i < 5; i++) {
      round.choose(true);
      round.choose(false);
      round.choose(true);
      round.advance();
    }
    expect(round.score, 2);
    expect(round.selections, everyElement(isTrue));
    expect(round.phase, RoundPhase.readyToSubmit);
    expect(round.selections, hasLength(5));
  });

  test(
    'T05 replay creates new ID and resets answers after verification',
    () async {
      final store = MemoryTestStore();
      final round = await completed(store);
      final id = round.roundId;
      await round.submit();
      await round.startRound();
      expect(round.roundId, isNot(id));
      expect(round.score, 0);
      expect(round.selections, everyElement(isNull));
      expect(round.index, 0);
    },
  );

  test('T06 double submit commits exactly once', () async {
    final store = MemoryTestStore()..commitGate = Completer<void>();
    final round = await completed(store);
    final first = round.submit();
    await round.submit();
    expect(store.commits, 1);
    expect(round.canSignOut, isFalse);
    expect(round.canReplay, isFalse);
    store.commitGate!.complete();
    await first;
    expect(round.phase, RoundPhase.cloudVerified);
    expect(store.records, hasLength(1));
    expect(round.verified!.correctCount, 2);
  });

  test('T09 acknowledged commit plus denied verification retains ID and retries only read', () async {
    final store = MemoryTestStore()
      ..readFault = const CloudProblem(
        'permission-denied',
        '[DEVELOPMENT INJECTION]',
      );
    final round = await completed(store);
    final id = round.roundId;
    await round.submit();
    expect(round.writeAcknowledged, isTrue);
    expect(round.phase, RoundPhase.permissionDenied);
    expect(
      round.message,
      contains('Write acknowledged; verification unavailable.'),
    );
    expect(round.canReplay, isFalse);
    expect(round.canSignOut, isFalse);
    await round.startRound();
    await round.submit();
    expect(round.roundId, id);
    expect(store.commits, 1);
    await round.retryVerification();
    expect(round.phase, RoundPhase.cloudVerified);
    expect(store.commits, 1);
    expect(store.reads, 2);
  });

  test(
    'T08 commit timeout retains operation lock until original settles',
    () async {
      final store = MemoryTestStore()..commitGate = Completer<void>();
      final round = await completed(
        store,
        timeout: const Duration(milliseconds: 10),
      );
      final id = round.roundId;
      await round.submit();
      expect(round.phase, RoundPhase.saveUnknown);
      expect(round.operationActive, isTrue);
      await round.retryVerification();
      await round.submit();
      expect(store.reads, 0);
      expect(store.commits, 1);
      store.commitGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(round.operationActive, isFalse);
      expect(round.roundId, id);
      await round.retryVerification();
      expect(round.phase, RoundPhase.cloudVerified);
      expect(store.commits, 1);
    },
  );

  test(
    'T08 offline failure requires server absence before same-ID resubmit',
    () async {
      final store = MemoryTestStore()
        ..commitFault = const CloudProblem('unavailable', 'offline');
      final round = await completed(store);
      final id = round.roundId;
      await round.submit();
      await round.submit();
      expect(store.commits, 1);
      store.commitFault = null;
      await round.retryVerification();
      expect(round.phase, RoundPhase.readyToSubmit);
      expect(round.roundId, id);
      await round.submit();
      expect(round.phase, RoundPhase.cloudVerified);
      expect(store.records, hasLength(1));
    },
  );

  test('read timeout cannot overlap another server read', () async {
    final store = MemoryTestStore()..readGate = Completer<ServerAttempt?>();
    final round = await completed(
      store,
      timeout: const Duration(milliseconds: 10),
    );
    await round.submit();
    expect(round.phase, RoundPhase.verificationUnavailable);
    await round.retryVerification();
    expect(store.reads, 1);
    expect(round.operationActive, isTrue);
    store.readGate!.complete(store.records.values.single);
    await Future<void>.delayed(Duration.zero);
    store.readGate = null;
    await round.retryVerification();
    expect(round.phase, RoundPhase.cloudVerified);
  });

  test(
    'T07 fresh controller retrieves original ID without questions or writes',
    () async {
      final store = MemoryTestStore();
      final first = await completed(store);
      await first.submit();
      final restart = RoundController(Questions(), store)
        ..identityChanged('user-A');
      await restart.retrieve(first.roundId!);
      expect(restart.phase, RoundPhase.cloudVerified);
      expect(restart.questions, isEmpty);
      expect(store.commits, 1);
    },
  );

  test(
    'T12 unavailable and quota errors stay distinct and manually recover',
    () async {
      for (final code in [
        'unavailable',
        'resource-exhausted',
        'unauthenticated',
      ]) {
        final store = MemoryTestStore()
          ..readFault = CloudProblem(code, 'injected');
        final round = await completed(store);
        await round.submit();
        expect(round.errorCode, code);
        expect(round.phase, RoundPhase.verificationUnavailable);
        expect(round.writeAcknowledged, isTrue);
        expect(round.canReplay, isFalse);
        await round.retryVerification();
        expect(round.phase, RoundPhase.cloudVerified);
        expect(store.commits, 1);
      }
    },
  );

  test('G01 collision preserves winning payload', () async {
    final store = MemoryTestStore();
    final round = await completed(store);
    store.records['user-A/${round.roundId}'] = ServerAttempt(
      'user-A',
      round.roundId!,
      5,
      DateTime.utc(2026),
    );
    await round.submit();
    expect(round.phase, RoundPhase.collision);
    expect(store.records.values.single.correctCount, 5);
    expect(round.canReplay, isTrue);
  });

  test(
    'G03 stale commit after account switch cannot modify new screen',
    () async {
      final store = MemoryTestStore()..commitGate = Completer<void>();
      final round = await completed(store);
      final pending = round.submit();
      round.identityChanged('user-B');
      store.commitGate!.complete();
      await pending;
      expect(round.uid, 'user-B');
      expect(round.phase, RoundPhase.idle);
      expect(round.roundId, isNull);
      expect(round.writeAcknowledged, isFalse);
      expect(round.verified, isNull);
    },
  );

  test(
    'G03 stale server read after account switch cannot update new result',
    () async {
      final store = MemoryTestStore()..readGate = Completer<ServerAttempt?>();
      final round = await completed(store);
      final pending = round.submit();
      await Future<void>.delayed(Duration.zero);
      round.identityChanged('user-B');
      store.readGate!.complete(store.records.values.single);
      await pending;
      expect(round.uid, 'user-B');
      expect(round.phase, RoundPhase.idle);
      expect(round.verified, isNull);
      expect(round.operationActive, isFalse);
      expect(round.questions, isEmpty);
    },
  );

  test('server validation rejects extra fields, unresolved timestamps, and numeric type drift', () {
    final a = const FrozenAttempt('a', 'id', 2);
    final valid = {...a.fixedFields, 'submittedAt': Timestamp.now()};
    expect(validateServerAttempt('a', 'id', valid).correctCount, 2);
    for (final invalid in [
      {...valid, 'extra': true},
      {...valid, 'submittedAt': null},
      {...valid, 'correctCount': 6},
      {...valid, 'correctCount': 2.0},
      {...valid, 'schemaVersion': 1.0},
      {...valid, 'variant': 'A'},
    ]) {
      expect(
        () => validateServerAttempt('a', 'id', invalid),
        throwsA(isA<CloudProblem>()),
      );
    }
  });
}
