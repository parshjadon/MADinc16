// Generate local native configuration from ignored private key values.
const fs = require('node:fs');
const source = 'private/firebase.local.json';
if (!fs.existsSync(source)) throw Error('Copy firebase.local.example.json to ' + source + ' and fill it privately.');
const values = JSON.parse(fs.readFileSync(source, 'utf8'));
for (const name of ['FIREBASE_ANDROID_API_KEY','FIREBASE_WEB_API_KEY']) {
  if (typeof values[name] !== 'string' || !values[name]) throw Error('Missing private setting: ' + name);
}
fs.mkdirSync('android/app', {recursive:true});
fs.writeFileSync('android/app/google-services.json', JSON.stringify({
  project_info:{project_number:'459037828954',project_id:'inc06-f77f6',storage_bucket:'inc06-f77f6.firebasestorage.app'},
  client:[{
    client_info:{mobilesdk_app_id:'1:459037828954:android:db59f65fd4f07d5b24f563',android_client_info:{package_name:'edu.uca.parsh.science_signal'}},
    oauth_client:[],api_key:[{current_key:values.FIREBASE_ANDROID_API_KEY}],services:{appinvite_service:{other_platform_oauth_client:[]}},
  }],configuration_version:'1',
},null,2));
fs.writeFileSync('web/firebase-config.json',JSON.stringify({
  projectId:'inc06-f77f6',appId:'1:459037828954:web:54ae572aa2d3209c24f563',
  apiKey:values.FIREBASE_WEB_API_KEY,authDomain:'inc06-f77f6.firebaseapp.com',
  messagingSenderId:'459037828954',storageBucket:'inc06-f77f6.firebasestorage.app',
},null,2));
console.log('Generated ignored Android/web configuration. Key values were not printed.');
