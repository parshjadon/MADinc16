# Repository instructions

The user requires **no literal API keys, tokens, passwords, private keys, service
accounts or credential-bearing artifacts in GitHub**, including Firebase client
configuration keys. Treat this as a standing publishing constraint.

- Keep actual configuration in ignored `private/` files. Track empty examples only.
- Do not track generated native Firebase configuration. Dart options must obtain
  key values from build-time settings, never string literals.
- Run `node tool/scan_secrets.cjs --staged` before commits and
  `node tool/scan_secrets.cjs --all-refs` before every push.
- Install this repository's hooks with `node tool/install_hooks.cjs` in a new clone.
- Never upload APKs to a public release: Firebase client keys are embedded in them.
  Keep the release APK local for submission through the course portal.
- Scan Word reports and other public artifacts before upload. Never print secrets
  in commands, logs, test failures, PR descriptions or chat output.
- When cleaning a leak, preserve a private backup, revoke the exposed key, clean
  every published branch/tag, verify the replacement locally and use explicit
  force-with-lease checks. Do not weaken deployed Firestore rules or enable billing.
