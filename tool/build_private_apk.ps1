$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskRoot
node tool/configure_firebase.cjs
if ($LASTEXITCODE -ne 0) { throw 'Private Firebase configuration is missing.' }
$taskBuildLog = Join-Path $taskRoot 'private\release-build.log'
flutter build apk --release --target-platform android-arm64,android-x64 --dart-define-from-file=private/firebase.local.json *> $taskBuildLog
if ($LASTEXITCODE -ne 0) { throw "Build failed. Inspect the private local log at $taskBuildLog; never publish it." }
New-Item -ItemType Directory -Force -Path (Join-Path $taskRoot 'submission') | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot 'build\app\outputs\flutter-apk\app-release.apk') -Destination (Join-Path $taskRoot 'submission\ICA16_B_ParshJadon.apk') -Force
Write-Output 'Private release APK built at submission/ICA16_B_ParshJadon.apk. Do not upload it to GitHub.'
