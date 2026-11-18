import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class CloudProblem implements Exception {
  const CloudProblem(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

@immutable
class FrozenAttempt {
  const FrozenAttempt(this.uid, this.roundId, this.correctCount);
  final String uid;
  final String roundId;
  final int correctCount;

  Map<String, dynamic> get fixedFields => {
    'schemaVersion': 1,
    'variant': 'B',
    'categoryId': 17,
    'questionCount': 5,
    'correctCount': correctCount,
  };

  bool matches(Map<String, dynamic> data) => fixedFields.entries.every(
    (e) =>
        data[e.key].runtimeType == e.value.runtimeType &&
        data[e.key] == e.value,
  );
}

@immutable
class ServerAttempt {
  const ServerAttempt(
    this.uid,
    this.roundId,
    this.correctCount,
    this.submittedAt,
  );
  final String uid;
  final String roundId;
  final int correctCount;
  final DateTime submittedAt;
}

abstract interface class AttemptStore {
  String newId(String uid);
  Future<void> commit(FrozenAttempt attempt);
  Future<ServerAttempt?> read(String uid, String roundId);
}

enum VerificationFault {
  none,
  permissionDenied,
  unavailable,
  resourceExhausted,
}

/// Faults exist only in debug builds, before a server read, after a REAL commit.
/// They never replace the transaction or change deployed security rules.
class FirestoreAttemptStore implements AttemptStore {
  FirestoreAttemptStore(this.firestore, this.auth);
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  VerificationFault _nextFault = VerificationFault.none;
  String? _faultRound;

  void injectAfterNextCommit(VerificationFault fault) {
    if (kDebugMode) _nextFault = fault;
  }

  DocumentReference<Map<String, dynamic>> reference(String uid, String id) =>
      firestore.collection('users').doc(uid).collection('attempts').doc(id);

  void _requireOwner(String uid) {
    if (auth.currentUser?.uid != uid) {
      throw const CloudProblem(
        'unauthenticated',
        'The initiating user is no longer signed in.',
      );
    }
  }

  @override
  String newId(String uid) => reference(uid, '_').parent.doc().id;

  @override
  Future<void> commit(FrozenAttempt attempt) async {
    _requireOwner(attempt.uid);
    if (attempt.correctCount < 0 || attempt.correctCount > 5) {
      throw const CloudProblem(
        'invalid-argument',
        'Score must be an integer from 0 through 5.',
      );
    }
    final ref = reference(attempt.uid, attempt.roundId);
    // This frozen map is constructed once, OUTSIDE the retryable callback.
    final payload = Map<String, dynamic>.unmodifiable({
      ...attempt.fixedFields,
      'submittedAt': FieldValue.serverTimestamp(),
    });
    await firestore.runTransaction<void>(
      (transaction) async {
        final original = await transaction.get(ref);
        if (!original.exists) {
          transaction.set(ref, payload);
        } else if (!attempt.matches(original.data()!)) {
          throw const CloudProblem(
            'collision',
            'This round ID already contains a different score. Original preserved.',
          );
        }
      },
      maxAttempts: 3,
      timeout: const Duration(seconds: 30),
    );
    if (kDebugMode && _nextFault != VerificationFault.none) {
      _faultRound = '${attempt.uid}/${attempt.roundId}';
    }
  }

  @override
  Future<ServerAttempt?> read(String uid, String roundId) async {
    _requireOwner(uid);
    if (kDebugMode && _faultRound == '$uid/$roundId') {
      final fault = _nextFault;
      _nextFault = VerificationFault.none;
      _faultRound = null;
      if (fault != VerificationFault.none) {
        final code = switch (fault) {
          VerificationFault.permissionDenied => 'permission-denied',
          VerificationFault.unavailable => 'unavailable',
          VerificationFault.resourceExhausted => 'resource-exhausted',
          VerificationFault.none => throw StateError('unreachable'),
        };
        throw CloudProblem(
          code,
          '[DEVELOPMENT INJECTION] First verification read failed.',
        );
      }
    }
    final snapshot = await reference(
      uid,
      roundId,
    ).get(const GetOptions(source: Source.server));
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw const CloudProblem(
        'unverified',
        'Read is cached or contains pending writes.',
      );
    }
    if (!snapshot.exists) return null;
    return validateServerAttempt(uid, roundId, snapshot.data()!);
  }
}

ServerAttempt validateServerAttempt(
  String uid,
  String id,
  Map<String, dynamic> d,
) {
  final score = d['correctCount'];
  final timestamp = d['submittedAt'];
  final expected = FrozenAttempt(uid, id, score is int ? score : -1);
  if (d.length != 6 ||
      !expected.matches(d) ||
      score is! int ||
      score < 0 ||
      score > 5 ||
      timestamp is! Timestamp) {
    throw const CloudProblem(
      'invalid-record',
      'Server record does not match the exact Class B schema.',
    );
  }
  return ServerAttempt(uid, id, score, timestamp.toDate());
}
