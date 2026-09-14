const fs = require('fs');
const auth = require('C:/Users/khenc/nodejs/node_modules/firebase-tools/lib/auth.js');
async function main() {
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw Error('Firebase CLI login required');
  const token = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
  const headers = {Authorization: `Bearer ${token.access_token}`, 'Content-Type':'application/json'};
  const base = 'https://firestore.googleapis.com/v1/projects/toocoob/databases/(default)/documents';
  const r = await fetch(base + ':runQuery', {method:'POST',headers,body:JSON.stringify({structuredQuery:{from:[{collectionId:'users'}],where:{fieldFilter:{field:{fieldPath:'nickname'},op:'EQUAL',value:{stringValue:'Чоно'}}}}})});
  if (!r.ok) throw Error(`Profile query failed: ${r.status}`);
  const docs = (await r.json()).filter(x=>x.document).map(x=>x.document);
  const matches = docs.filter(d=>d.fields.firstName?.stringValue === 'Хэнчбиш' && d.fields.lastName?.stringValue?.startsWith('Б'));
  console.log(JSON.stringify(docs.map(d=>({id:d.name.split('/').pop(),firstName:d.fields.firstName?.stringValue,lastName:d.fields.lastName?.stringValue,nickname:d.fields.nickname?.stringValue,hasAvatar:!!d.fields.photoUrl})))) ;
  if (!['--apply', '--firestore-image'].includes(process.argv[2])) return;
  if(matches.length !== 1) throw Error('Expected exactly one confirmed profile');
  const doc=matches[0], uid=doc.name.split('/').pop();
  if(doc.fields.photoUrl?.stringValue) throw Error('Profile already has an avatar; refusing to overwrite');
  const bucket='toocoob.firebasestorage.app', object=`avatars/${uid}/legacy-chono.jpg`;
  const bytes=fs.readFileSync('assets/players/chono.jpg');
  if(process.argv[2] === '--firestore-image') {
    if(bytes.length > 150000) throw Error('Image too large for inline profile avatar');
    if(doc.fields.avatarBase64) throw Error('An inline avatar already exists');
    const encoded = bytes.toString('base64');
    const patch=await fetch('https://firestore.googleapis.com/v1/'+doc.name+'?updateMask.fieldPaths=avatarBase64&updateMask.fieldPaths=avatarContentType&currentDocument.updateTime='+encodeURIComponent(doc.updateTime),{method:'PATCH',headers,body:JSON.stringify({fields:{avatarBase64:{stringValue:encoded},avatarContentType:{stringValue:'image/jpeg'}}})});
    if(!patch.ok) throw Error(`Profile avatar update failed: ${patch.status}`);
    const verify=await fetch('https://firestore.googleapis.com/v1/'+doc.name,{headers});
    const saved=await verify.json();
    if(saved.fields?.avatarBase64?.stringValue !== encoded) throw Error('Avatar verification failed');
    console.log('Verified: avatar saved in Firebase Firestore profile ('+bytes.length+' bytes).');
    return;
  }
  const downloadToken=require('crypto').randomUUID();
  const boundary='avatar_'+require('crypto').randomUUID();
  const metadata=JSON.stringify({name:object,contentType:'image/jpeg',metadata:{firebaseStorageDownloadTokens:downloadToken}});
  const body=Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Type: application/json\r\n\r\n${metadata}\r\n--${boundary}\r\nContent-Type: image/jpeg\r\n\r\n`),bytes,Buffer.from(`\r\n--${boundary}--\r\n`)]);
  const upload=await fetch(`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o?uploadType=multipart&ifGenerationMatch=0`,{method:'POST',headers:{Authorization:headers.Authorization,'Content-Type':`multipart/related; boundary=${boundary}`},body});
  if(!upload.ok) {
    const error = await upload.json().catch(()=>({}));
    throw Error(`Avatar upload failed: ${upload.status}: ${error.error?.message || 'No details'}`);
  }
  const url=`https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(object)}?alt=media&token=${downloadToken}`;
  const patch=await fetch('https://firestore.googleapis.com/v1/'+doc.name+'?updateMask.fieldPaths=photoUrl&currentDocument.updateTime='+encodeURIComponent(doc.updateTime),{method:'PATCH',headers,body:JSON.stringify({fields:{photoUrl:{stringValue:url}}})});
  if(!patch.ok) throw Error(`Profile update failed: ${patch.status}`);
  const verify=await fetch('https://firestore.googleapis.com/v1/'+doc.name,{headers});
  const saved=await verify.json();
  const photo=await fetch(url);
  if(saved.fields?.photoUrl?.stringValue !== url || !photo.ok || (await photo.arrayBuffer()).byteLength !== bytes.length) throw Error('Verification failed');
  console.log('Verified: Firebase avatar uploaded and profile linked.');
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
