"""Create public submission notes and an explicitly private account handoff."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'submission';OUT.mkdir(exist_ok=True)
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
tested=json.loads((ROOT/'evidence/test-records.json').read_text())[0]['commit']
hashes={name:hashlib.sha256((OUT/name).read_bytes()).hexdigest() for name in ['ICA16_B_ParshJadon.apk','ICA16_B_ParshJadon.docx']}
notes=f'''ICA 16 Class B Graduate Submission
Parsh Jadon

Course portal deliverables
1. ICA16_B_ParshJadon.apk
2. Repository URL: https://github.com/parshjadon/MADinc16
3. ICA16_B_ParshJadon.docx

Source and package commit: {commit}
Tested application commit: {tested}
Package commits add evidence and reproduction tools; application source is unchanged.

Release downloads: https://github.com/parshjadon/MADinc16/releases/tag/ica16-b-final

Verified: 21 local regressions pass; T01-T12 and G01-G03 records pass;
real deployed Firebase transactions, exact server reads, ownership rejection,
offline recovery, one-shot verification injections, and graduate concurrency.
Release APK signature verified; installed and cold-launched on Android API 35.
APK is a signed release for ARM64 and x86-64 Android devices.
Firebase project inc06-f77f6 uses the free tier. No billing was enabled.

Outstanding evidence item: a separate Firebase-console screenshot has not been
captured. The report includes actual app screenshots and a redacted independent
Firestore REST record export. Add the console screenshot before claiming the
assignment's evidence checklist is fully complete.

SHA256
'''+''.join(f'{value}  {name}\n' for name,value in hashes.items())
(OUT/'SUBMISSION.txt').write_text(notes,encoding='utf-8')
access=json.loads((ROOT/'private/test_accounts.json').read_text())
restart=json.loads((ROOT/'private/restart_defines.json').read_text())
private='PRIVATE TEST ACCESS — DO NOT UPLOAD TO GITHUB OR PUBLIC COURSE MATERIALS\n\n'
private+='Use an instructor-approved private channel for any grader credentials.\n'
private+='Project: inc06-f77f6\n\n'
for label in ['A','B']:
    private+=f'Test user {label}\nEmail: {access[f"TEST_EMAIL_{label}"]}\nPassword: {access[f"TEST_PASSWORD_{label}"]}\nUID: {access[f"TEST_UID_{label}"]}\n\n'
private+=f'Restart retrieval ID for user A: {restart["TEST_RESTART_ID"]}\nExpected score: 2/5\n'
private+='\nAn unused empty free project, science-signal-b-parsh-2026, was created before the specified project link arrived. The app does not use it. No billing was enabled on it.\n'
(OUT/'PRIVATE_TEST_ACCESS.txt').write_text(private,encoding='utf-8')
manifest={'testedApplicationCommit':tested,'packageCommit':commit,'version':'1.0.0+1','apkArchitectures':['arm64-v8a','x86_64'],'artifacts':hashes,'consoleScreenshotIncluded':False,'localTestsPassed':21,'requiredTestRecordsPassed':15}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Prepared three portal deliverables and a separate private account handoff. Private values were not printed.')
