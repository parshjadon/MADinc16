// Uses existing Git Credential Manager authorization; never prints credentials.
const fs = require('node:fs');
const cp = require('node:child_process');
async function main() {
  const raw = cp.execFileSync('git', ['credential','fill'], {
    input:'protocol=https\nhost=github.com\npath=parshjadon/MADinc16.git\n\n',
    encoding:'utf8', env:{...process.env,GIT_TERMINAL_PROMPT:'0',GCM_INTERACTIVE:'never'},
    stdio:['pipe','pipe','pipe'],
  });
  const credential=Object.fromEntries(raw.trim().split(/\r?\n/).map(line=>{
    const p=line.indexOf('='); return [line.slice(0,p),line.slice(p+1)];
  }));
  if(!credential.password) throw Error('GitHub credential unavailable; git push can still be attempted.');
  const headers={Authorization:`Bearer ${credential.password}`,Accept:'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'};
  async function request(url, method='GET', body, extra={}) {
    const response=await fetch(url,{method,headers:{...headers,...extra},body});
    const data=await response.json();
    if(!response.ok) throw Error(`GitHub ${response.status}: ${data.message||'request failed'}`);
    return data;
  }
  const repo=await request('https://api.github.com/repos/parshjadon/MADinc16');
  console.log(`Repository accessible; visibility ${repo.private?'private':'public'}; push permission ${!!repo.permissions?.push}.`);
  if(process.argv[2]!=='publish') return;
  const commit=cp.execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
  let release;
  const existing=await fetch('https://api.github.com/repos/parshjadon/MADinc16/releases/tags/ica16-b-final',{headers});
  if(existing.status===200) release=await existing.json();
  else if(existing.status===404) release=await request('https://api.github.com/repos/parshjadon/MADinc16/releases','POST',JSON.stringify({
    tag_name:'ica16-b-final',target_commitish:commit,name:'ICA16 Class B — Parsh Jadon',draft:false,prerelease:false,
    body:'Graduate Science Signal submission: signed 64-bit Android release APK and evidence document. Uses the free Firebase project inc06-f77f6. Deployed-cloud tests cover immutable transactions, same-ID verification recovery, ownership rules and G01–G03 concurrency. See the README and evidence document for actual observations, AI disclosure and reproduction instructions. A separate Firebase-console screenshot remains outstanding; actual app screenshots and an independent Firestore record export are included. No test passwords or signing keys are distributed.',
  }),{'Content-Type':'application/json'});
  else throw Error(`Release lookup failed: ${existing.status}`);
  const uploaded=[];
  for(const name of ['ICA16_B_ParshJadon.apk','ICA16_B_ParshJadon.docx','SUBMISSION.txt']) {
    if(release.assets.some(a=>a.name===name)) throw Error(`Release already contains ${name}; refusing to replace an existing asset.`);
    const content=fs.readFileSync(`submission/${name}`);
    const asset=await request(`https://uploads.github.com/repos/parshjadon/MADinc16/releases/${release.id}/assets?name=${encodeURIComponent(name)}`,'POST',content,{'Content-Type':'application/octet-stream'});
    uploaded.push({name:asset.name,url:asset.browser_download_url,size:asset.size});
  }
  fs.writeFileSync('submission/github-release.json',JSON.stringify({url:release.html_url,commit,assets:uploaded},null,2));
  console.log(`Published release ${release.html_url}; ${uploaded.length} final assets uploaded.`);
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
