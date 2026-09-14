const fs=require('node:fs');
const path=require('node:path');
const root=process.env.FIREBASE_TOOLS_DIR;
if(!root)throw Error('Set FIREBASE_TOOLS_DIR to the installed firebase-tools directory');
const auth=require(path.join(root,'lib/auth'));
const {Client}=require(path.join(root,'lib/apiv2'));
auth.setActiveAccount({},auth.getGlobalDefaultAccount());
const project='toocoob';
const prefix='/databases/(default)/documents/';
const parent={ownerUserId:'owner',playerUserIds:['owner','viewer'],tableRegistrarUserIds:{'1':'owner','2':'viewer'}};
const state={stateKey:'session',gameKey:'muushig',writerUserId:'owner',registrarUserId:'owner',revision:1,payloadJson:'{}',playerUserIds:['owner','viewer'],savedSessionId:'live_test'};
const cases=[];
function add(name,uid,method,doc,expectation,before,after,registrar='owner'){
 cases.push({name,test:{expectation,request:{auth:uid?{uid,token:{}}:null,method,path:prefix+doc,resource:after?{data:after}:null},resource:before?{data:before}:null,functionMocks:[
 {function:'get',args:[{exactValue:prefix+'active_tables/test'}],result:{value:{data:parent}}},
 {function:'get',args:[{exactValue:prefix+'active_tables/test/game_states/session'}],result:{value:{data:{...state,registrarUserId:registrar}}}},
 ]}});
}
const doc='active_tables/test/game_states/session';
add('owner creates','owner','create',doc,'ALLOW',null,state);
add('viewer reads','viewer','get',doc,'ALLOW',state);
add('stranger denied','stranger','get',doc,'DENY',state);
add('anonymous denied',null,'get',doc,'DENY',state);
add('viewer write denied','viewer','update',doc,'DENY',state,{...state,writerUserId:'viewer',revision:2});
add('owner transfers','owner','update',doc,'ALLOW',state,{...state,registrarUserId:'viewer',revision:2});
add('new registrar writes','viewer','update',doc,'ALLOW',{...state,registrarUserId:'viewer',revision:2},{...state,writerUserId:'viewer',registrarUserId:'viewer',revision:3},'viewer');
add('stale revision denied','owner','update',doc,'DENY',{...state,revision:3},{...state,revision:2});
add('registrar updates checkpoint','viewer','update','active_tables/test','ALLOW',parent,{...parent,savedSessionId:'live_test'},'viewer');
add('registrar cannot seize ownership','viewer','update','active_tables/test','DENY',parent,{...parent,ownerUserId:'viewer'},'viewer');
(async()=>{
 const client=new Client({urlPrefix:'https://firebaserules.googleapis.com',apiVersion:'v1'});
 const result=await client.post(`/projects/${project}:test`,{source:{files:[{name:'firestore.rules',content:fs.readFileSync('firestore.rules','utf8')}]},testSuite:{testCases:cases.map(c=>c.test)}},{skipLog:{body:true,resBody:true}});
 const body=result.body;
 if(body.issues?.length) console.log(JSON.stringify(body.issues));
 const results=body.testResults??[];
 results.forEach((r,i)=>console.log(cases[i].name, r.state, r.state==='SUCCESS'?'':JSON.stringify(r)));
 if(results.length!==cases.length||results.some(r=>r.state!=='SUCCESS'))process.exitCode=1;
 else console.log(`${results.length} server-side rules tests passed; no production documents changed.`);
})().catch(e=>{console.error(e.message);process.exitCode=1});
