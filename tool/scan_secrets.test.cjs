const {test}=require('node:test');
const assert=require('node:assert/strict');
const {findings,prohibitedPath,inspectPublicArtifact}=require('./scan_secrets.cjs');
test('detects a generated key without storing a key literal',()=>{
  assert.deepEqual(findings('apiKey: '+['AI','za','x'.repeat(35)].join('')),['Google API key']);
});
test('detects credential assignments without echoing credential text',()=>{
  assert.ok(findings('password = '+JSON.stringify('x'.repeat(32))).includes('Credential assignment'));
});
test('allows empty examples and environment-based values',()=>{
  assert.deepEqual(findings('apiKey: String.fromEnvironment("FIREBASE_WEB_API_KEY")'),[]);
  assert.deepEqual(findings('{"FIREBASE_WEB_API_KEY":""}'),[]);
});
test('blocks credential-bearing generated files and public APKs',()=>{
  for (const path of ['private/settings.json','android/app/google-services.json','web/firebase-config.json','.env.production','result.apk','release.jks']) assert.equal(prohibitedPath(path),true);
  for (const path of ['firebase.local.example.json','.env.example','lib/firebase_options.dart']) assert.equal(prohibitedPath(path),false);
});
test('public upload guard rejects APKs before opening them',()=>{
  assert.throws(()=>inspectPublicArtifact('must-not-publish.apk'),/prohibited/);
});
