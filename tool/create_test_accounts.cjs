// Creates two non-personal test accounts in the configured Firebase project.
// Writes secrets only to ignored private/test_accounts.json; never prints them.
const fs = require('node:fs');
const crypto = require('node:crypto');
async function main() {
  fs.mkdirSync('private', {recursive:true});
  if (fs.existsSync('private/test_accounts.json')) {
    console.log('Private test accounts already exist.'); return;
  }
  const config = JSON.parse(fs.readFileSync('web/firebase-config.json', 'utf8'));
  const accounts = {};
  for (const label of ['A', 'B']) {
    const email = `ica16-${label.toLowerCase()}-${crypto.randomBytes(3).toString('hex')}@science-signal.example`;
    const password = crypto.randomBytes(24).toString('base64url') + 'aA9!';
    const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${config.apiKey}`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({email, password, returnSecureToken: false}),
    });
    const data = await response.json();
    if (!response.ok) throw Error(`Account ${label}: ${data.error?.message}`);
    accounts[`TEST_EMAIL_${label}`] = email;
    accounts[`TEST_PASSWORD_${label}`] = password;
    accounts[`TEST_UID_${label}`] = data.localId;
  }
  fs.writeFileSync('private/test_accounts.json', JSON.stringify(accounts, null, 2));
  console.log('Created test users A and B. Credentials saved privately, excluded from Git.');
}
main().catch(e => { console.error(e.message); process.exitCode = 1; });
