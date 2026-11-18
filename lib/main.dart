import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'attempt_store.dart';
import 'firebase_options.dart';
import 'quiz.dart';
import 'round_controller.dart';

const ink = Color(0xFF142D37);
const mint = Color(0xFF0C736B);
const paper = Color(0xFFF2F6F5);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    runApp(const ScienceSignalApp());
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Firebase could not initialize. Check your connection and app configuration.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: main,
                    child: const Text('Retry initialization'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScienceSignalApp extends StatelessWidget {
  const ScienceSignalApp({super.key, this.controller});
  final RoundController? controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Science Signal',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: mint, surface: Colors.white),
      scaffoldBackgroundColor: paper,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontWeight: FontWeight.w800,
          color: ink,
          height: 1.15,
        ),
        headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: ink),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: ink),
        bodyLarge: TextStyle(color: ink, height: 1.5),
        bodyMedium: TextStyle(color: ink, height: 1.45),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: mint,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: SignalHome(roundOverride: controller),
  );
}

class SignalHome extends StatefulWidget {
  const SignalHome({super.key, this.roundOverride});
  final RoundController? roundOverride;
  @override
  State<SignalHome> createState() => _SignalHomeState();
}

class _SignalHomeState extends State<SignalHome> {
  late final FirestoreAttemptStore store;
  late final RoundController round;
  StreamSubscription<User?>? authChanges;
  final email = TextEditingController();
  final password = TextEditingController();
  final retrieveId = TextEditingController();
  bool signingIn = false;
  bool showPassword = false;
  VerificationFault fault = VerificationFault.none;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    store = FirestoreAttemptStore(
      FirebaseFirestore.instance,
      FirebaseAuth.instance,
    );
    round = widget.roundOverride ?? RoundController(OpenTriviaSource(), store);
    round.identityChanged(FirebaseAuth.instance.currentUser?.uid);
    authChanges = FirebaseAuth.instance.authStateChanges().listen(
      (user) => round.identityChanged(user?.uid),
    );
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          (round.questionsSource.retryAfter > Duration.zero ||
              round.phase == RoundPhase.requestError)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    authChanges?.cancel();
    if (widget.roundOverride == null) round.dispose();
    email.dispose();
    password.dispose();
    retrieveId.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (signingIn) return;
    FocusScope.of(context).unfocus();
    setState(() => signingIn = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
      password.clear();
    } on FirebaseAuthException catch (error) {
      final readable = switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => 'Email or password is incorrect.',
        'network-request-failed' =>
          'Cannot reach authentication. Check your connection.',
        'too-many-requests' =>
          'Too many sign-in attempts. Please wait and try again.',
        'user-disabled' => 'This test account has been disabled.',
        _ => 'Sign-in failed (${error.code}). Please retry.',
      };
      round.authError(error.code, readable);
    } catch (_) {
      round.authError(
        'unavailable',
        'Sign-in is unavailable. Check your connection.',
      );
    } finally {
      if (mounted) setState(() => signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: round,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        backgroundColor: paper,
        foregroundColor: ink,
        title: const Row(
          children: [
            Icon(Icons.science_outlined, color: mint),
            SizedBox(width: 10),
            Text(
              'Science Signal',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ],
        ),
        actions: [
          if (round.uid != null)
            IconButton(
              tooltip: round.canSignOut
                  ? 'Sign out'
                  : 'Resolve this round before signing out',
              onPressed: round.canSignOut
                  ? () async {
                      try {
                        await FirebaseAuth.instance.signOut();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not sign out. Please retry.',
                              ),
                            ),
                          );
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.logout_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  eyebrow('CLASS B  /  SCIENCE & NATURE'),
                  const SizedBox(height: 16),
                  if (round.uid == null)
                    ...signInPanel(context)
                  else ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          color: mint,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Authenticated · ${round.uid}',
                            key: const Key('identity'),
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (round.phase == RoundPhase.idle ||
                        round.phase == RoundPhase.requestError)
                      ...welcome(context),
                    if (round.phase == RoundPhase.loading)
                      panel(
                        child: const Padding(
                          padding: EdgeInsets.all(30),
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 20),
                              Text('Gathering five science questions…'),
                            ],
                          ),
                        ),
                      ),
                    if (round.phase == RoundPhase.playing) ...question(context),
                    if (round.questions.isNotEmpty &&
                        round.phase != RoundPhase.playing &&
                        round.phase != RoundPhase.loading)
                      ...review(context),
                    if (round.roundId != null &&
                        ![
                          RoundPhase.playing,
                          RoundPhase.loading,
                          RoundPhase.requestError,
                        ].contains(round.phase)) ...[
                      const SizedBox(height: 18),
                      cloudStatus(context),
                    ],
                    if ([
                          RoundPhase.idle,
                          RoundPhase.cloudVerified,
                        ].contains(round.phase) &&
                        !round.unresolved) ...[
                      const SizedBox(height: 22),
                      retrieve(context),
                    ],
                  ],
                  const SizedBox(height: 26),
                  const Text(
                    'Questions: Open Trivia Database · CC BY-SA 4.0\nScience Signal · ICA 16 · Parsh Jadon',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xFF5E747B)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget eyebrow(String text) => Text(
    text,
    style: const TextStyle(
      color: mint,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.8,
    ),
  );
  Widget panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFDCE7E5)),
    ),
    child: child,
  );

  List<Widget> signInPanel(BuildContext context) => [
    Text(
      'A little curiosity.\nFive discoveries.',
      style: Theme.of(context).textTheme.headlineLarge,
    ),
    const SizedBox(height: 12),
    const Text(
      'Test your science instincts, then follow your result all the way to the cloud.',
      style: TextStyle(fontSize: 16, height: 1.5),
    ),
    const SizedBox(height: 24),
    panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome to the lab',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text('Sign in with your authorized test account.'),
          const SizedBox(height: 22),
          TextField(
            key: const Key('email'),
            controller: email,
            enabled: !signingIn,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('password'),
            controller: password,
            enabled: !signingIn,
            obscureText: !showPassword,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => signIn(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(
                  showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          if (round.phase == RoundPhase.authError) ...[
            const SizedBox(height: 14),
            Text(
              '${round.message} (${round.errorCode})',
              key: const Key('authError'),
              style: const TextStyle(color: Color(0xFFA52E3D)),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('signIn'),
            onPressed: signingIn ? null : signIn,
            child: Text(signingIn ? 'Signing in…' : 'Enter the lab'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> welcome(BuildContext context) => [
    Text(
      'Ready to investigate?',
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    const SizedBox(height: 10),
    const Text(
      'Five medium questions about the natural world. Choose once, review everything, and verify your score on the server.',
    ),
    const SizedBox(height: 20),
    panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '05 QUESTIONS',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'TRUE / FALSE',
                style: TextStyle(color: mint, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (round.phase == RoundPhase.requestError) ...[
            Text(
              round.message,
              style: const TextStyle(color: Color(0xFFA52E3D)),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton(
            key: const Key('startRound'),
            onPressed: round.questionsSource.retryAfter > Duration.zero
                ? null
                : round.startRound,
            child: Text(
              round.questionsSource.retryAfter > Duration.zero
                  ? 'Retry in ${round.questionsSource.retryAfter.inSeconds + 1}s'
                  : round.phase == RoundPhase.requestError
                  ? 'Retry questions'
                  : 'Start a science round',
            ),
          ),
        ],
      ),
    ),
  ];

  List<Widget> question(BuildContext context) {
    final q = round.questions[round.index];
    final answer = round.selections[round.index];
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Question ${round.index + 1} of 5',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text('${round.score} points', style: const TextStyle(color: mint)),
        ],
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: (round.index + 1) / 5,
          minHeight: 7,
          backgroundColor: const Color(0xFFDCE7E5),
        ),
      ),
      const SizedBox(height: 24),
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            eyebrow('MEDIUM  ·  SCIENCE & NATURE'),
            const SizedBox(height: 18),
            Text(
              q.prompt,
              key: const Key('questionPrompt'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: ink,
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                for (final choice in [true, false]) ...[
                  if (!choice) const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      key: Key(choice ? 'answerTrue' : 'answerFalse'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: answer == choice
                            ? (choice == q.correct
                                  ? const Color(0xFFDAF1E8)
                                  : const Color(0xFFFBE4E7))
                            : null,
                        disabledForegroundColor: ink,
                        side: BorderSide(
                          color: answer == choice
                              ? (choice == q.correct
                                    ? mint
                                    : const Color(0xFFA52E3D))
                              : const Color(0xFFD0DEDB),
                          width: 1.5,
                        ),
                      ),
                      onPressed: answer == null
                          ? () => round.choose(choice)
                          : null,
                      child: Text(
                        choice ? 'True' : 'False',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (answer != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    answer == q.correct
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: answer == q.correct ? mint : const Color(0xFFA52E3D),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      round.message,
                      key: const Key('answerFeedback'),
                    ),
                  ),
                ],
              )
            else
              const Text(
                'Select an answer to continue.',
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 22),
            FilledButton(
              key: const Key('continue'),
              onPressed: answer == null ? null : round.advance,
              child: Text(round.index == 4 ? 'Review all answers' : 'Continue'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> review(BuildContext context) => [
    Text(
      'Your round, in review',
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    const SizedBox(height: 10),
    Text(
      '${round.score} / 5',
      key: const Key('score'),
      style: const TextStyle(
        fontSize: 52,
        fontWeight: FontWeight.w800,
        color: mint,
      ),
    ),
    const Text('Every answer is final. Every result has a record.'),
    const SizedBox(height: 20),
    for (var i = 0; i < round.questions.length; i++) ...[
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  round.selections[i] == round.questions[i].correct
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  color: round.selections[i] == round.questions[i].correct
                      ? mint
                      : const Color(0xFFA52E3D),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${i + 1}. ${round.questions[i].prompt}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Your answer: ${round.selections[i] == true ? 'True' : 'False'}   ·   Correct: ${round.questions[i].correct ? 'True' : 'False'}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
    ],
    if (kDebugMode && round.canSubmit) ...[
      DropdownButtonFormField<VerificationFault>(
        initialValue: fault,
        decoration: const InputDecoration(
          labelText: 'Development only: first post-commit read',
        ),
        items: VerificationFault.values
            .map((f) => DropdownMenuItem(value: f, child: Text(f.name)))
            .toList(),
        onChanged: (f) {
          if (f != null) setState(() => fault = f);
        },
      ),
      const SizedBox(height: 12),
    ],
    if (round.phase == RoundPhase.readyToSubmit)
      FilledButton(
        key: const Key('submit'),
        onPressed: round.canSubmit
            ? () {
                if (kDebugMode) store.injectAfterNextCommit(fault);
                round.submit();
              }
            : null,
        child: const Text('Submit this result'),
      ),
  ];

  Widget cloudStatus(BuildContext context) {
    final success = round.phase == RoundPhase.cloudVerified;
    final pending = round.operationActive;
    final color = success ? mint : const Color(0xFF9A6200);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFE0F1EB) : const Color(0xFFFFF2D8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                success ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  success
                      ? 'Cloud verified'
                      : round.writeAcknowledged
                      ? 'Write acknowledged'
                      : 'Cloud status',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(round.message, key: const Key('cloudMessage')),
          if (round.errorCode != null)
            Text(
              'Code: ${round.errorCode}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 12),
          SelectableText(
            'Round ID: ${round.roundId}',
            key: const Key('roundId'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: round.roundId!));
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Round ID copied. Keep it to retrieve after restart.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('Copy round ID'),
          ),
          if (round.verified != null)
            Text(
              'Server score: ${round.verified!.correctCount}/5\nSubmitted: ${round.verified!.submittedAt.toUtc().toIso8601String()}\nSource: server · Pending writes: false',
              key: const Key('serverProof'),
              style: const TextStyle(fontSize: 12),
            ),
          if (pending) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Waiting for the original operation. Retries are locked.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (round.reconciliationRequired) ...[
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('retryVerification'),
              onPressed: pending ? null : round.retryVerification,
              child: Text(
                round.writeAcknowledged
                    ? 'Retry server verification'
                    : 'Reconcile this round ID',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Replay and sign-out stay locked until this result is resolved.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (round.canReplay) ...[
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('replay'),
              onPressed: round.questionsSource.retryAfter > Duration.zero
                  ? null
                  : round.startRound,
              child: const Text('Play a new round'),
            ),
          ],
        ],
      ),
    );
  }

  Widget retrieve(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text(
      'Retrieve a previous result',
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    subtitle: const Text(
      'Restarted? Read the original ID from the server.',
      style: TextStyle(fontSize: 12),
    ),
    children: [
      const SizedBox(height: 12),
      TextField(
        key: const Key('retrieveId'),
        controller: retrieveId,
        decoration: const InputDecoration(labelText: 'Round document ID'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('retrieve'),
        onPressed: () => round.retrieve(retrieveId.text.trim()),
        icon: const Icon(Icons.cloud_download_outlined),
        label: const Text('Read exact server record'),
      ),
      const SizedBox(height: 12),
    ],
  );
}
