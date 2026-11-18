"""Check public candidates and release files against the private test credentials."""
import json, subprocess, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
credentials=json.loads((ROOT/'private/test_accounts.json').read_text())
test_secrets=[v.encode() for v in credentials.values() if isinstance(v,str)]
secrets=list(test_secrets)
for name in ['private/firebase.local.json','private/security/exposed-values.json']:
    f=ROOT/name
    if f.exists():
        raw=json.loads(f.read_text())
        values=raw.values() if isinstance(raw,dict) else raw
        secrets.extend(v.encode() for v in values if isinstance(v,str))
names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')
hits=[]
for name in filter(None,names):
    f=ROOT/name
    if not f.is_file():continue
    content=f.read_bytes()
    if any(s in content for s in secrets):hits.append(name)
for name in ['ICA16_B_ParshJadon.apk','ICA16_B_ParshJadon.docx']:
    with zipfile.ZipFile(ROOT/'submission'/name) as archive:
        for member in archive.namelist():
            blocked=test_secrets if name.endswith('.apk') else secrets
            if any(s in archive.read(member) for s in blocked):hits.append(name+':'+member)
if hits: raise SystemExit('Private test values detected in public candidates: '+', '.join(hits))
print('Public source/report candidates contain none of the private test or Firebase key values.')
print('The APK is private-only and contains client configuration as required by Firebase. Test credentials are absent from it.')
