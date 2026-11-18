// Dependency-free scanner for staged files and the complete reachable Git history.
const cp = require('node:child_process');
const fs = require('node:fs');
const zlib = require('node:zlib');
const rules = [
  ['Google API key', /AIza[0-9A-Za-z_-]{35}/],
  ['GitHub token', /(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})/],
  ['AWS access key', /(?:AKIA|ASIA)[A-Z0-9]{16}/],
  ['Private key', /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/],
  ['Slack token', /xox[baprs]-[A-Za-z0-9-]{20,}/],
  ['Credential assignment', /(?:password|secret|access_token|refresh_token|client_secret)\s*[=:]\s*["'][A-Za-z0-9+_/.=-]{16,}["']/i],
];
function findings(content) {
  const text = Buffer.isBuffer(content) ? content.toString('utf8') : content;
  return rules.filter(([,pattern])=>pattern.test(text)).map(([name])=>name);
}
function git(args, input) { return cp.execFileSync('git',args,{input,encoding:'utf8',maxBuffer:32*1024*1024}); }
function prohibitedPath(name) {
  return /(?:^|\/)private\//.test(name) || /(?:^|\/)(?:google-services\.json|firebase-config\.json|GoogleService-Info\.plist|key\.properties)$/.test(name) ||
    /\.(?:apk|aab|jks|keystore|p12|pfx|pem|key)$/i.test(name) ||
    /(?:^|\/)\.env(?:$|\.(?!example$|template$))/.test(name);
}
function scan(mode) {
  const failures=[];
  if (mode==='--all-refs') {
    // Only Git branches/tags/remote branches are publishable. Local agent snapshot
    // trees under refs/codex are private tooling state, not repository history.
    const refs=git(['for-each-ref','--format=%(refname)','refs/heads','refs/tags','refs/remotes']).trim().split('\n').filter(Boolean);
    const objects=git(['rev-list','--objects',...refs]).trim().split('\n');
    const seen=new Set();
    for (const line of objects) {
      const space=line.indexOf(' '); if (space<0) continue;
      const oid=line.slice(0,space), name=line.slice(space+1); if (seen.has(oid)) continue;
      seen.add(oid);
      if (git(['cat-file','-t',oid]).trim()!=='blob') continue;
      const content=cp.execFileSync('git',['cat-file','blob',oid],{maxBuffer:32*1024*1024});
      if (content.includes(0)) continue;
      for (const rule of findings(content)) failures.push({path:name,object:oid.slice(0,12),rule});
    }
  } else {
    const names=git(['diff','--cached','--name-only','--diff-filter=ACMR','-z']).split('\0').filter(Boolean);
    for (const name of names) {
      if (prohibitedPath(name)) failures.push({path:name,rule:'Private/configuration artifact is prohibited'});
      const content=cp.execFileSync('git',['show',':'+name],{maxBuffer:32*1024*1024});
      if (content.includes(0)) continue;
      for (const rule of findings(content)) failures.push({path:name,rule});
    }
  }
  if (failures.length) {
    console.error('Push/commit blocked. Credential values are not printed.');
    failures.forEach(f=>console.error(JSON.stringify(f)));
    return false;
  }
  console.log(mode==='--all-refs'?'Secret scan passed for every reachable Git branch/tag.':'Secret scan passed for staged changes.');
  return true;
}
function inspectPublicArtifact(file) {
  if (/\.(?:apk|aab)$/i.test(file)) throw Error('Public Android uploads are prohibited because they contain Firebase client configuration.');
  const data=fs.readFileSync(file);
  const contents=[data];
  if (/\.(?:docx|xlsx|pptx|zip)$/i.test(file)) {
    let end=-1;
    for(let i=data.length-22;i>=Math.max(0,data.length-65557);i--) {
      if(data.readUInt32LE(i)===0x06054b50){end=i;break;}
    }
    if(end<0) throw Error('Public artifact ZIP structure could not be inspected.');
    let pos=data.readUInt32LE(end+16), total=0;
    const count=data.readUInt16LE(end+10);
    for(let i=0;i<count;i++) {
      if(data.readUInt32LE(pos)!==0x02014b50) throw Error('Invalid artifact ZIP directory.');
      const method=data.readUInt16LE(pos+10), compressed=data.readUInt32LE(pos+20), size=data.readUInt32LE(pos+24);
      const local=data.readUInt32LE(pos+42);
      total+=size; if(total>128*1024*1024) throw Error('Artifact inspection size limit exceeded.');
      const start=local+30+data.readUInt16LE(local+26)+data.readUInt16LE(local+28);
      const bytes=data.subarray(start,start+compressed);
      if(method!==0 && method!==8) throw Error('Unsupported artifact compression.');
      contents.push(method===0?bytes:zlib.inflateRawSync(bytes,{maxOutputLength:128*1024*1024}));
      pos+=46+data.readUInt16LE(pos+28)+data.readUInt16LE(pos+30)+data.readUInt16LE(pos+32);
    }
  }
  const known=[];
  for(const name of ['private/test_accounts.json','private/firebase.local.json','private/security/exposed-values.json']) {
    if(fs.existsSync(name)) for(const value of Object.values(JSON.parse(fs.readFileSync(name,'utf8')))) {
      if(typeof value==='string' && value.length>10) known.push(Buffer.from(value));
    }
  }
  for(const content of contents) {
    if(findings(content).length || known.some(secret=>content.includes(secret))) throw Error('Private values detected in public artifact '+file+'; values are not printed.');
  }
  return true;
}
if (require.main===module) {
  if(process.argv[2]==='--artifact') {
    try { inspectPublicArtifact(process.argv[3]);console.log('Public artifact secret scan passed.'); }
    catch(error){console.error(error.message);process.exitCode=1;}
  } else process.exitCode=scan(process.argv[2] || '--staged')?0:1;
}
module.exports={findings,prohibitedPath,inspectPublicArtifact};
