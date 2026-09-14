const assert = require('node:assert/strict');
const project='demo-toocoob-sync';
const base=`http://127.0.0.1:8187/v1/projects/${project}/databases/(default)/documents`;
const token=uid => `${Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url')}.${Buffer.from(JSON.stringify({sub:uid,user_id:uid,aud:project,iss:`https://securetoken.google.com/${project}`,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600,firebase:{sign_in_provider:'custom'}})).toString('base64url')}.`;
function encode(v){if(v===null)return {nullValue:null};if(typeof v==='string')return {stringValue:v};if(typeof v==='number')return {integerValue:String(v)};if(Array.isArray(v))return {arrayValue:{values:v.map(encode)}};return {mapValue:{fields:Object.fromEntries(Object.entries(v).map(([k,x])=>[k,encode(x)]))}};}
async function request(uid,path,method='GET',data){const r=await fetch(`${base}/${path}`,{method,headers:{Authorization:`Bearer ${token(uid)}`,'Content-Type':'application/json'},body:data?JSON.stringify({fields:encode(data).mapValue.fields}):undefined});const t=await r.text();return {status:r.status,text:t};}
(async()=>{
 const table='active_tables/test';const path=table+'/game_states/session';
 let r=await request('owner',table,'PATCH',{ownerUserId:'owner',playerUserIds:['owner','viewer'],status:'active',tableRegistrarUserIds:{'1':'owner','2':'viewer'}});assert.equal(r.status,200,r.text);
 const state={stateKey:'session',gameKey:'muushig',writerUserId:'owner',registrarUserId:'owner',revision:1,payloadJson:'{}',playerUserIds:['owner','viewer'],savedSessionId:'live_test'};
 r=await request('owner',path,'PATCH',state);assert.equal(r.status,200,r.text);
 assert.equal((await request('viewer',path)).status,200);
 assert.equal((await request('stranger',path)).status,403);
 assert.equal((await request('viewer',path,'PATCH',{...state,writerUserId:'viewer',revision:2})).status,403);
 r=await request('owner',path,'PATCH',{...state,registrarUserId:'viewer',revision:2});assert.equal(r.status,200,r.text);
 r=await request('viewer',path,'PATCH',{...state,writerUserId:'viewer',registrarUserId:'viewer',revision:3});assert.equal(r.status,200,r.text);
 assert.equal((await request('owner',path,'PATCH',{...state,revision:2})).status,403);
 r=await request('viewer',`${table}?updateMask.fieldPaths=savedSessionId`,'PATCH',{savedSessionId:'live_test'});assert.equal(r.status,200,r.text);
 assert.equal((await request('viewer',`${table}?updateMask.fieldPaths=ownerUserId`,'PATCH',{ownerUserId:'viewer'})).status,403);
 console.log('Firestore rules: 9 owner/viewer/transfer/revision checks passed.');
})().catch(e=>{console.error(e);process.exitCode=1});
