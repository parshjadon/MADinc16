const cp=require('node:child_process');
cp.execFileSync('git',['config','core.hooksPath','.githooks']);
console.log('Installed repository commit/push secret checks.');
