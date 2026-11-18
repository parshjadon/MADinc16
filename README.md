# Science Signal — ICA 16 Class B

Graduate submission by **Parsh Jadon**, November 17, 2026.

Download the updated Word report and submission notes from the [private-configuration release](https://github.com/parshjadon/MADinc16/releases/tag/ica16-b-private-config). The signed APK is kept **locally** at `submission/ICA16_B_ParshJadon.apk` for private course-portal submission. It is not published to GitHub because compiled Firebase apps contain their client configuration. The report includes all test records, app screenshots, the matching redacted Firebase-console screenshot, and deployed-record corroboration.

Flutter Android science quiz backed by real Firebase Authentication and Cloud Firestore. Exactly five medium Science & Nature boolean questions are requested from Open Trivia Database, URL-component decoded, validated, answered once, and reviewed. Completed scores use an immutable create-once transaction and an exact server-only confirmation read.

## Run

Prerequisites: Flutter 3.47.2 / Dart 3.13.2, Android SDK, JDK 17 or newer, an authorized Email/Password test account. The configured project is **inc06-f77f6**, Firestore `(default)`, Standard edition, Native mode, `nam5`. The database was created with `freeTier: true`. No billing account or paid upgrade is required or enabled by this project.

```powershell
flutter pub get
node tool/install_hooks.cjs
# Copy firebase.local.example.json to private/firebase.local.json and fill it privately.
node tool/configure_firebase.cjs
flutter run -d <android-device-id> --dart-define-from-file=private/firebase.local.json
```

`lib/firebase_options.dart` contains project identifiers and environment lookups only. Actual API keys are in ignored `private/firebase.local.json`; `tool/configure_firebase.cjs` generates ignored native/web configuration locally. No literal keys, test passwords or release signing material may be committed or published. Obtain instructor test access through an approved private channel.

## Release APK

```powershell
powershell -ExecutionPolicy Bypass -File tool/configure_signing.ps1
powershell -ExecutionPolicy Bypass -File tool/build_private_apk.ps1
```

The APK supports ARM64 phones and x86-64 Android emulators. A Windows Application Control policy blocks this machine's Flutter **32-bit ARM** AOT compiler; the 64-bit compilers build normally. This is a release build with a private RSA signing key, not a debug APK. Output: `build/app/outputs/flutter-apk/app-release.apk`. The final submission copy is named `ICA16_B_ParshJadon.apk`.

Keep this APK out of public repositories and releases. Submit it directly through the private course portal. API-key values cannot be hidden from somebody who possesses a compiled Firebase client; authorization still depends on Firebase Authentication and deployed owner-only rules.

On other systems, generate a keystore with `keytool` and create the ignored `android/key.properties` containing `storePassword`, `keyPassword`, `keyAlias`, and `storeFile`. Keep the key for future upgrades. The provided PowerShell helper uses the Android Studio JDK at `JAVA_HOME`, falling back to this machine's configured location.

## Cloud setup and rules

The chosen Firebase project must be separate from a Class A project because Class B has a different exact schema. Enable standard Email/Password sign-in under Authentication and create two non-personal test accounts. Create the free Standard / Native Firestore database and deploy:

```powershell
firebase login
firebase deploy --only firestore:rules --project inc06-f77f6
```

The app writes **only** `users/{FirebaseAuth.currentUser.uid}/attempts/{roundId}` with exactly these fields:

| Field | Value |
| --- | --- |
| schemaVersion | integer 1 |
| variant | string B |
| categoryId | integer 17 |
| questionCount | integer 5 |
| correctCount | integer 0–5 |
| submittedAt | server timestamp |

No names, emails, question text, passwords, tokens, or duplicate `roundId` field are saved in attempt documents. All unmatched paths are denied. Existing attempts cannot be updated or deleted by clients.

## Recovery behavior

`RoundController` keeps `writeAcknowledged`, `reconciliationRequired`, `operationActive`, and `verified` separate. A committed write followed by a denied read shows **“Write acknowledged; verification unavailable.”** Retry reads the original reference; it does not create another attempt. A 10-second UI timeout never cancels the underlying SDK operation. The original future keeps the retry lock until it settles; reconciliation checks the same ID before another transaction is allowed. A server-confirmed absence permits same-ID resubmission. A different existing score is a collision and is never overwritten.

Replay and sign-out are disabled while unresolved. Each callback checks the initiating generation, UID, and round ID. Externally changed authentication invalidates old callbacks. Firestore persistence is disabled; no local score database or preferences fallback exists.

### Reproduce the required contradiction

1. Run a debug build, sign in as test user A, and complete a round.
2. In the **Development only: first post-commit read** selector, choose `permissionDenied`.
3. Submit once. A **real deployed-cloud transaction** completes. Only the next verification read is injected with `permission-denied`; the amber status explicitly labels the injection.
4. Inspect that exact document in the Firebase console. Do not change the deployed rules.
5. Tap **Retry server verification**. The one-shot fault has been consumed; the app performs a real `Source.server` get of the same ID and turns green only after full validation.

These hooks are guarded by `kDebugMode` and omitted from release UI. `unavailable` and `resourceExhausted` are also one-shot development injections. No actual quota is deliberately exhausted.

### Restart retrieval

1. After **Cloud verified**, copy the round document ID; store it outside the app for the demonstration.
2. Force-stop and reopen the app while online. Sign in as the **same authorized user** if needed.
3. Expand **Retrieve a previous result**, paste that ID, and select **Read exact server record**.
4. Check score, resolved timestamp, `Source: server`, and `Pending writes: false`. No questions are replayed and no new document is written.

## Verification

```powershell
flutter analyze
flutter test --reporter expanded
```

`test/` contains isolated local regression checks. Its explicitly named test doubles are **not cloud proof**. The deployed suite uses the real FlutterFire implementation:

```powershell
# Create disposable test accounts only if the project owner authorizes it.
node tool/create_test_accounts.cjs
$testedCommit = git rev-parse HEAD
flutter drive --driver=test_driver/integration_driver.dart `
  --target=integration_test/cloud_test.dart -d <android-device-id> `
  --dart-define-from-file=private/test_accounts.json `
  --dart-define-from-file=private/firebase.local.json `
  --dart-define=APP_COMMIT=$testedCommit
```

`private/test_accounts.json` must contain `TEST_EMAIL_A`, `TEST_PASSWORD_A`, `TEST_EMAIL_B`, and `TEST_PASSWORD_B`. It is ignored. **Never distribute an integration-test APK:** test credentials are compiled into that temporary build. The submitted release is built separately without those defines. Build logs from integration commands are kept private because Gradle can echo base64 Dart defines.

The live suite uses two independently initialized Firebase app/auth/Firestore clients. G01 submits conflicting scores at one ID, G02 submits unrelated IDs concurrently, and G03 delays delivery of an actual server response across an actual account change. Deployed rules reject user B's access, score 6, extra fields, and updates. Quota/permission fault injections are explicitly identified.

## Credential prevention and history

The exposed Firebase client keys were replaced with Firebase-only restricted keys kept in ignored private configuration. Previously published key values were revoked, public APK assets were removed, and all published branches/tags were sanitized. Original test-run commit identifiers remain historical provenance; `evidence/history-rewrite-map.json` maps them to sanitized history.

Commit and push hooks run `tool/scan_secrets.cjs`. The scanner blocks literal Google/GitHub/AWS/Slack keys, private keys, credential assignments, generated credential files and public Android artifacts. GitHub Actions repeats the full-history check. Public release tooling scans document ZIP contents and never uploads APKs. Use `node --test tool/scan_secrets.test.cjs` to test these guards. The user's global Codex instructions retain this publishing preference for future work.

## Source map

* `lib/quiz.dart`: exact endpoint, 10-second GET, five-second request gate, strict parsing.
* `lib/round_controller.dart`: quiz state, frozen score, timeout locks, reconciliation, identity guards.
* `lib/attempt_store.dart`: side-effect-free transaction callback, exact schema verification, debug fault hook.
* `lib/main.dart`: sign-in, fixed True/False controls, review, recovery and restart retrieval screens.
* `firestore.rules`: deployed owner-only schema and immutability contract.
* `integration_test/cloud_test.dart`: reproducible deployed-cloud observations.
* `evidence/`: final redacted evidence, state diagrams, test records and analyses.

## Attribution and assistance

Open Trivia Database provides questions under [CC BY-SA 4.0](https://opentdb.com/api_config.php). Firebase behavior was checked against official [Flutter setup](https://firebase.google.com/docs/flutter/setup), [transactions](https://firebase.google.com/docs/firestore/manage-data/transactions), and [server/cache reads](https://firebase.google.com/docs/firestore/query-data/get-data) documentation.

OpenAI Codex assisted substantially with implementation, tests, debugging, documentation and report generation on November 17, 2026. The evidence distinguishes actual deployed observations, explicitly labelled development injections, and local unit tests. The student should be prepared to reproduce the failure and explain the implementation during an instructor check.
