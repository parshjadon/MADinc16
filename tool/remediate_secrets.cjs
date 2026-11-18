// Repository-specific remediation. Never print API keys or authorization tokens.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

const projectNumber = '459037828954';
const repo = 'parshjadon/MADinc16';
async function credentials() {
  const base = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
  const auth = require(path.join(base, 'auth.js'));
  const google = await auth.getAccessToken(auth.getGlobalDefaultAccount().tokens.refresh_token, [
    'https://www.googleapis.com/auth/cloud-platform', 'https://www.googleapis.com/auth/firebase',
  ]);
  const raw = cp.execFileSync('git', ['credential', 'fill'], {
    input: 'protocol=https\nhost=github.com\npath=' + repo + '.git\n\n', encoding: 'utf8',
    env: {...process.env, GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'never'}, stdio: ['pipe','pipe','pipe'],
  });
  const token = raw.split(/\r?\n/).find(s => s.startsWith('password='))?.slice(9);
  if (!token) throw Error('Existing GitHub credential unavailable.');
  return {google: google.access_token, github: token};
}

async function main() {
  fs.mkdirSync('private/security', {recursive:true});
  const auth = await credentials();
  async function request(provider, endpoint, method = 'GET', body) {
    const response = await fetch(endpoint, {
      method, headers: {
        Authorization: 'Bearer ' + auth[provider], 'Content-Type': 'application/json',
        ...(provider === 'github' ? {Accept:'application/vnd.github+json', 'X-GitHub-Api-Version':'2022-11-28'} : {}),
      }, body: body === undefined ? undefined : JSON.stringify(body),
    });
    const data = response.status === 204 ? {} : await response.json();
    if (!response.ok) throw Error(provider + ' ' + response.status + ': ' + (data.message || data.error?.message || 'Request failed'));
    return data;
  }
  const command = process.argv[2] || 'inventory';
  if (command === 'inventory') {
    const keys = await request('google', 'https://apikeys.googleapis.com/v2/projects/' + projectNumber + '/locations/global/keys');
    const alerts = await request('github', 'https://api.github.com/repos/' + repo + '/secret-scanning/alerts?per_page=100');
    const releases = await request('github', 'https://api.github.com/repos/' + repo + '/releases?per_page=100');
    fs.writeFileSync('private/security/inventory.json', JSON.stringify({keys,alerts,releases},null,2));
    console.log(JSON.stringify({
      keys:(keys.keys || []).map(k=>({name:k.name,displayName:k.displayName,restrictions:k.restrictions})),
      alerts:alerts.map(a=>({number:a.number,type:a.secret_type,state:a.state})),
      releases:releases.map(r=>({id:r.id,tag:r.tag_name,assets:r.assets.map(a=>({id:a.id,name:a.name}))})),
    },null,2));
  } else if (command === 'create-private-replacements') {
    const configPath='private/firebase.local.json';
    if (fs.existsSync(configPath)) {
      console.log('Private replacement configuration already exists.'); return;
    }
    const services=['identitytoolkit.googleapis.com','securetoken.googleapis.com','firestore.googleapis.com','firebaseinstallations.googleapis.com','firebase.googleapis.com'];
    const config={}; const created=[];
    for (const platform of ['ANDROID','WEB']) {
      const op=await request('google','https://apikeys.googleapis.com/v2/projects/'+projectNumber+'/locations/global/keys','POST',{
        displayName:'Science Signal '+platform.toLowerCase()+' private build configuration',
        restrictions:{apiTargets:services.map(service=>({service}))},
      });
      let result=op;
      for (let attempt=0; !result.done && attempt<30; attempt++) {
        await new Promise(resolve=>setTimeout(resolve,1000));
        result=await request('google','https://apikeys.googleapis.com/v2/'+op.name);
      }
      if (!result.done || result.error) throw Error('Replacement key operation did not complete.');
      const name=result.response.name;
      const value=await request('google','https://apikeys.googleapis.com/v2/'+name+'/keyString');
      config['FIREBASE_'+platform+'_API_KEY']=value.keyString;
      created.push({platform,name,services});
    }
    fs.writeFileSync(configPath,JSON.stringify(config,null,2));
    fs.writeFileSync('private/security/replacement-metadata.json',JSON.stringify(created,null,2));
    console.log('Created two Firebase-only restricted replacement keys in ignored private configuration. No values printed.');
  } else if (command === 'remove-public-apks') {
    const releases=await request('github','https://api.github.com/repos/'+repo+'/releases?per_page=100');
    for (const release of releases) {
      for (const asset of release.assets.filter(a=>/\.(?:apk|aab)$/i.test(a.name))) {
        await request('github','https://api.github.com/repos/'+repo+'/releases/assets/'+asset.id,'DELETE');
        console.log('Removed public credential-bearing Android asset from '+release.tag_name+'.');
      }
      const body='Public APK download removed at the owner\'s request because Firebase client keys are embedded in compiled apps. The updated APK is kept locally for private course-portal submission. Source configuration is being sanitized; see the repository README for current instructions.';
      await request('github','https://api.github.com/repos/'+repo+'/releases/'+release.id,'PATCH',{body});
    }
  } else if (command === 'verify-private-replacements') {
    const values=JSON.parse(fs.readFileSync('private/firebase.local.json','utf8'));
    const accounts=JSON.parse(fs.readFileSync('private/test_accounts.json','utf8'));
    for (const [name,key] of Object.entries(values)) {
      const r=await fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key='+encodeURIComponent(key),{
        method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({email:accounts.TEST_EMAIL_A,password:accounts.TEST_PASSWORD_A,returnSecureToken:true}),
      });
      const data=await r.json();
      if (!r.ok || data.localId!==accounts.TEST_UID_A) {
        const safeCode = String(data.error?.message || 'UID_MISMATCH').split(' : ')[0].replace(/AIza[0-9A-Za-z_-]{35}/g,'[REDACTED]');
        throw Error('Private replacement authentication check failed for '+name+': HTTP '+r.status+' '+safeCode+'.');
      }
      console.log(name+': real authentication verified; token values not logged.');
    }
  } else if (command === 'revoke-exposed') {
    const inventory=JSON.parse(fs.readFileSync('private/security/inventory.json','utf8'));
    const replacementNames=JSON.parse(fs.readFileSync('private/security/replacement-metadata.json','utf8')).map(k=>k.name);
    for (const key of inventory.keys.keys || []) {
      if (replacementNames.includes(key.name)) throw Error('Refusing to revoke a replacement.');
      await request('google','https://apikeys.googleapis.com/v2/'+key.name,'DELETE');
      console.log('Revoked the previously published '+key.displayName+'.');
    }
    fs.writeFileSync('private/security/revoked.json',JSON.stringify({time:new Date().toISOString(),names:(inventory.keys.keys || []).map(k=>k.name)},null,2));
  } else if (command === 'close-alerts') {
    if (!fs.existsSync('private/security/revoked.json')) throw Error('Revoke exposed keys before resolving alerts.');
    const alerts=await request('github','https://api.github.com/repos/'+repo+'/secret-scanning/alerts?state=open&per_page=100');
    for (const alert of alerts) {
      if (alert.secret_type!=='google_api_key') continue;
      await request('github','https://api.github.com/repos/'+repo+'/secret-scanning/alerts/'+alert.number,'PATCH',{
        state:'resolved',resolution:'revoked',
        resolution_comment:'Exposed client key revoked. Replacement is restricted to Firebase APIs and kept only in ignored private build configuration. Public APK assets removed. Git history and published tags sanitized, with commit/push secret checks added.',
      });
      console.log('Resolved revoked-key alert #'+alert.number+'.');
    }
  } else if (command === 'verify-remediation') {
    const alerts=await request('github','https://api.github.com/repos/'+repo+'/secret-scanning/alerts?per_page=100');
    const oldValues=JSON.parse(fs.readFileSync('private/security/exposed-values.json','utf8'));
    const accounts=JSON.parse(fs.readFileSync('private/test_accounts.json','utf8'));
    for (let index=0; index<oldValues.length; index++) {
      const response=await fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key='+encodeURIComponent(oldValues[index]),{
        method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({email:accounts.TEST_EMAIL_A,password:accounts.TEST_PASSWORD_A,returnSecureToken:true}),
      });
      if (response.ok) throw Error('A revoked key still authenticates during provider propagation; verify again before finalizing.');
      console.log('Previously exposed key '+(index+1)+': rejected by authentication service.');
    }
    const released=await request('github','https://api.github.com/repos/'+repo+'/releases?per_page=100');
    if (released.some(r=>r.assets.some(a=>/\.(?:apk|aab)$/i.test(a.name)))) throw Error('A public APK asset remains.');
    if (alerts.some(a=>a.state==='open')) throw Error('GitHub still has open secret alerts.');
    const summary={time:new Date().toISOString(),alerts:alerts.map(a=>({number:a.number,state:a.state,resolution:a.resolution})),publicAndroidAssets:0,oldKeyAuthenticationRejected:true};
    fs.writeFileSync('private/security/final-verification.json',JSON.stringify(summary,null,2));
    console.log('GitHub has no open secret alerts and no public Android artifacts.');
  } else throw Error('Unknown remediation command.');
}
main().catch(error=>{console.error(error.message); process.exitCode=1;});
