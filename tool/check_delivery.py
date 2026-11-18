"""Check public candidates and release files against the private test credentials."""
import json, subprocess, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
credentials=json.loads((ROOT/'private/test_accounts.json').read_text())
secrets=[v.encode() for v in credentials.values() if isinstance(v,str)]
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
            if any(s in archive.read(member) for s in secrets):hits.append(name+':'+member)
if hits: raise SystemExit('Private test values detected in public candidates: '+', '.join(hits))
print('No private account emails, UIDs or passwords found in public source candidates or unpacked release files.')
print('Private folders, signing files, test APKs, SDK downloads and integration logs remain excluded from Git.')
