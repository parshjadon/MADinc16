// Independent, read-only console/API corroboration. This is NOT used for rule tests.
// Client-cloud tests always use Firebase Authentication and the deployed rules.
const fs = require('node:fs');
const path = require('node:path');
async function main() {
  const base = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
  const auth = require(path.join(base, 'auth.js'));
  const credentials = await auth.getAccessToken(auth.getGlobalDefaultAccount().tokens.refresh_token, [
    'https://www.googleapis.com/auth/cloud-platform', 'https://www.googleapis.com/auth/firebase',
  ]);
  const accounts = JSON.parse(fs.readFileSync('private/test_accounts.json', 'utf8'));
  const rawLog = fs.readFileSync('private/cloud-run-final.log');
  const log = rawLog.toString(rawLog[0] === 0xff && rawLog[1] === 0xfe ? 'utf16le' : 'utf8');
  const events = [...log.matchAll(/EVIDENCE (\{[^\r\n]*\})/g)].map(m => JSON.parse(m[1]));
  const targetEvents = ['T06', 'T09', 'G01', 'G02'].map(id => events.find(e => e.id === id));
  if (targetEvents.some(x => !x)) throw Error('Final cloud suite must finish before export.');
  const url = `https://firestore.googleapis.com/v1/projects/inc06-f77f6/databases/(default)/documents/users/${accounts.TEST_UID_A}/attempts?pageSize=100`;
  const r = await fetch(url, {headers: {Authorization: `Bearer ${credentials.access_token}`}});
  const data = await r.json();
  if (!r.ok) throw Error(`Firestore evidence export failed: ${r.status}`);
  const exported = targetEvents.map(e => {
    const doc = data.documents.find(d => d.name.endsWith(e.roundSuffix));
    if (!doc) throw Error(`Missing server evidence for ${e.id}`);
    const fields = Object.fromEntries(Object.entries(doc.fields).map(([k,v]) => [k,
      'integerValue' in v ? Number(v.integerValue) : v.stringValue ?? v.timestampValue]));
    if (e.id === 'T06') {
      const id = doc.name.split('/').pop();
      fs.writeFileSync('private/restart_defines.json', JSON.stringify({...accounts, TEST_RESTART_ID:id}));
    }
    return {testId:e.id, projectId:'inc06-f77f6', database:'(default)',
      uidSuffix:accounts.TEST_UID_A.slice(-6), roundSuffix:e.roundSuffix,
      fields, createTime:doc.createTime, updateTime:doc.updateTime,
      observedAt:new Date().toISOString(), source:'Independent read-only Firestore REST API export using project-owner CLI session. Client rule tests do not use this authority.'};
  });
  fs.mkdirSync('evidence', {recursive:true});
  fs.writeFileSync('evidence/server-console-export.json', JSON.stringify(exported,null,2));
  fs.writeFileSync('evidence/cloud-events.json',JSON.stringify(events,null,2));
  console.log('Exported four redacted deployed documents and final client-test events; private restart reference prepared.');
}
main().catch(e => {console.error(e.message);process.exitCode=1;});
