import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'attempt_store.dart';
import 'quiz.dart';

enum RoundPhase {
  signedOut,
  idle,
  loading,
  playing,
  readyToSubmit,
  submitting,
  verifying,
  cloudVerified,
  authError,
  requestError,
  saveUnknown,
  permissionDenied,
  verificationUnavailable,
  collision,
}

class RoundController extends ChangeNotifier {
  RoundController(
    this.questionsSource,
    this.store, {
    this.uiTimeout = const Duration(seconds: 10),
  });

  final QuestionSource questionsSource;
  final AttemptStore store;
  final Duration uiTimeout;
  RoundPhase phase = RoundPhase.signedOut;
  String? uid;
  String? roundId;
  String message = 'Sign in to begin your science round.';
  String? errorCode;
  List<ScienceQuestion> questions = const [];
  List<bool?> selections = [];
  int index = 0;
  bool writeAcknowledged = false;
  bool operationActive = false;
  bool reconciliationRequired = false;
  ServerAttempt? verified;
  FrozenAttempt? _frozen;
  int _generation = 0;
  bool _disposed = false;

  int get score => questions
      .asMap()
      .entries
      .where((e) => selections[e.key] == e.value.correct)
      .length;
  bool get unresolved =>
      operationActive ||
      reconciliationRequired ||
      (writeAcknowledged && verified == null && phase != RoundPhase.collision);
  bool get canReplay =>
      !unresolved &&
      uid != null &&
      (phase == RoundPhase.cloudVerified || phase == RoundPhase.collision);
  bool get canSignOut => !unresolved && phase != RoundPhase.loading;
  bool get canSubmit => phase == RoundPhase.readyToSubmit && !unresolved;
  String get suffix => roundId == null
      ? 'none'
      : roundId!.substring(roundId!.length > 6 ? roundId!.length - 6 : 0);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation, String user, String id) =>
      !_disposed && generation == _generation && uid == user && roundId == id;

  /// Also handles externally changed auth while an operation is unresolved.
  /// All old callbacks are invalidated before the new screen is notified.
  void identityChanged(String? nextUid) {
    if (uid == nextUid) return;
    _generation++;
    uid = nextUid;
    roundId = null;
    questions = const [];
    selections = [];
    index = 0;
    writeAcknowledged = false;
    operationActive = false;
    reconciliationRequired = false;
    verified = null;
    _frozen = null;
    errorCode = null;
    phase = nextUid == null ? RoundPhase.signedOut : RoundPhase.idle;
    message = nextUid == null
        ? 'Sign in to begin your science round.'
        : 'Five questions. One answer each. A result you can verify.';
    _emit();
  }

  void authError(String code, String readable) {
    if (uid != null) return;
    phase = RoundPhase.authError;
    errorCode = code;
    message = readable;
    _emit();
  }

  Future<void> startRound() async {
    if (uid == null ||
        unresolved ||
        phase == RoundPhase.loading ||
        phase == RoundPhase.playing ||
        phase == RoundPhase.readyToSubmit) {
      return;
    }
    final user = uid!;
    final generation = ++_generation;
    // Only round start allocates an ID; every recovery retains it.
    final id = store.newId(user);
    roundId = id;
    phase = RoundPhase.loading;
    message = 'Requesting five science questions…';
    errorCode = null;
    questions = const [];
    selections = [];
    verified = null;
    _frozen = null;
    writeAcknowledged = false;
    index = 0;
    _emit();
    try {
      final loaded = await questionsSource.load();
      if (!_current(generation, user, id)) return;
      questions = loaded;
      selections = List<bool?>.filled(5, null);
      phase = RoundPhase.playing;
      message = 'Choose True or False. Your answer is final.';
    } catch (error) {
      if (!_current(generation, user, id)) return;
      phase = RoundPhase.requestError;
      message = error is QuizException
          ? error.message
          : 'Could not load questions. Please retry.';
    }
    _emit();
  }

  void choose(bool answer) {
    if (phase != RoundPhase.playing || selections[index] != null) return;
    selections[index] = answer;
    message = answer == questions[index].correct
        ? 'Correct — one point earned.'
        : 'Incorrect — the correct answer is ${questions[index].correct ? 'True' : 'False'}.';
    _emit();
  }

  void advance() {
    if (phase != RoundPhase.playing || selections[index] == null) return;
    if (index == 4) {
      _frozen = FrozenAttempt(uid!, roundId!, score);
      phase = RoundPhase.readyToSubmit;
      message = 'All five answers are final. Review and submit your result.';
    } else {
      index++;
      message = 'Choose True or False. Your answer is final.';
    }
    _emit();
  }

  Future<void> submit() async {
    if (!canSubmit || _frozen == null) return;
    final attempt = _frozen!;
    final generation = _generation;
    phase = RoundPhase.submitting;
    message = 'Committing this round to your cloud account…';
    errorCode = null;
    operationActive = true;
    _emit();
    // timeout() stops waiting, but DOES NOT cancel the original operation.
    // The original future owns operationActive until it actually settles.
    final operation = store.commit(attempt);
    unawaited(
      operation.then<void>(
        (_) {
          if (!_current(generation, attempt.uid, attempt.roundId)) return;
          operationActive = false;
          writeAcknowledged = true;
          _emit();
        },
        onError: (Object error, StackTrace stack) {
          if (!_current(generation, attempt.uid, attempt.roundId)) return;
          operationActive = false;
          _emit();
        },
      ),
    );
    try {
      await operation.timeout(uiTimeout);
      if (!_current(generation, attempt.uid, attempt.roundId)) return;
      writeAcknowledged = true;
      reconciliationRequired = true;
      await _readOriginal();
    } on TimeoutException {
      if (!_current(generation, attempt.uid, attempt.roundId)) return;
      phase = RoundPhase.saveUnknown;
      reconciliationRequired = true;
      errorCode = 'deadline-exceeded';
      message = 'Save outcome unknown. The original operation may still finish. Reconcile this same round ID before retrying.';
      _emit();
    } catch (error) {
      if (!_current(generation, attempt.uid, attempt.roundId)) return;
      // Even a transport failure must be reconciled before another transaction.
      reconciliationRequired = true;
      _cloudError(error, verification: false);
    }
  }

  Future<void> retryVerification() async {
    if (uid == null ||
        roundId == null ||
        operationActive ||
        !reconciliationRequired) {
      return;
    }
    await _readOriginal();
  }

  Future<void> retrieve(String id) async {
    if (uid == null ||
        unresolved ||
        phase == RoundPhase.playing ||
        phase == RoundPhase.readyToSubmit ||
        phase == RoundPhase.loading) {
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      message = 'Enter a valid round document ID.';
      _emit();
      return;
    }
    _generation++;
    roundId = id;
    _frozen = null;
    questions = const [];
    selections = [];
    index = 0;
    verified = null;
    writeAcknowledged = false;
    reconciliationRequired = true;
    await _readOriginal();
  }

  Future<void> _readOriginal() async {
    if (operationActive || uid == null || roundId == null) return;
    final user = uid!;
    final id = roundId!;
    final generation = _generation;
    phase = RoundPhase.verifying;
    message = writeAcknowledged
        ? 'Write acknowledged. Checking the exact server record…'
        : 'Reading this exact round ID from the server…';
    operationActive = true;
    errorCode = null;
    _emit();
    final operation = store.read(user, id);
    unawaited(
      operation.then<void>(
        (_) {
          if (!_current(generation, user, id)) return;
          operationActive = false;
          _emit();
        },
        onError: (Object error, StackTrace stack) {
          if (!_current(generation, user, id)) return;
          operationActive = false;
          _emit();
        },
      ),
    );
    try {
      final record = await operation.timeout(uiTimeout);
      if (!_current(generation, user, id)) return;
      if (record == null) {
        // No operation is still running, and this was a SERVER absence.
        if (writeAcknowledged) {
          throw const CloudProblem(
            'invalid-record',
            'Acknowledged record is missing from the server. Contact your instructor.',
          );
        }
        reconciliationRequired = false;
        phase = _frozen == null ? RoundPhase.idle : RoundPhase.readyToSubmit;
        message =
            'Server confirmed this ID is absent. ${_frozen == null ? 'Check the ID or start a round.' : 'You may retry Submit with the same ID.'}';
      } else if (_frozen != null &&
          record.correctCount != _frozen!.correctCount) {
        reconciliationRequired = false;
        phase = RoundPhase.collision;
        message = 'ID collision: the server contains a different score. The original record was preserved.';
        errorCode = 'collision';
      } else {
        verified = record;
        reconciliationRequired = false;
        phase = RoundPhase.cloudVerified;
        message =
            'Cloud verified. Exact server record confirmed; no pending writes.';
      }
      _emit();
    } on TimeoutException {
      if (!_current(generation, user, id)) return;
      _cloudError(
        const CloudProblem(
          'deadline-exceeded',
          'Server read timed out after 10 seconds.',
        ),
        verification: true,
      );
    } catch (error) {
      if (!_current(generation, user, id)) return;
      _cloudError(error, verification: true);
    }
  }

  void _cloudError(Object error, {required bool verification}) {
    final code = error is CloudProblem
        ? error.code
        : error is FirebaseException
        ? error.code
        : 'unknown';
    final injected =
        error is CloudProblem &&
        error.message.contains('[DEVELOPMENT INJECTION]');
    errorCode = code;
    final detail = switch (code) {
      'permission-denied' =>
        'Permission denied. Check account access and deployed rules.',
      'unavailable' =>
        'Service unavailable. Check your network and retry when online.',
      'resource-exhausted' =>
        'Quota exhausted. Wait for service capacity before a manual retry.',
      'unauthenticated' => 'Authentication expired. Restore the initiating account to retrieve this round.',
      'collision' =>
        'ID collision. A different payload already exists; never overwrite it.',
      'deadline-exceeded' => 'The 10-second wait ended. The underlying operation may still be running.',
      'invalid-record' || 'unverified' =>
        'Server verification did not satisfy the Class B contract.',
      _ =>
        'Cloud operation could not be confirmed. Reconcile this original ID.',
    };
    if (code == 'collision') {
      reconciliationRequired = false;
      phase = RoundPhase.collision;
    } else if (code == 'permission-denied') {
      phase = RoundPhase.permissionDenied;
    } else {
      phase = verification
          ? RoundPhase.verificationUnavailable
          : RoundPhase.saveUnknown;
    }
    message =
        '${writeAcknowledged
            ? 'Write acknowledged; verification unavailable. '
            : verification
            ? 'Verification unavailable. '
            : 'Save outcome unconfirmed. '}$detail${injected ? ' [DEVELOPMENT INJECTION]' : ''}';
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
