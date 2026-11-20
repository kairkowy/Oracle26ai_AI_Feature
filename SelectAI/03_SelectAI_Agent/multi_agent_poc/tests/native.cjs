'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict'),readline=require('node:readline');
const ora=require(process.argv[2]||'oracledb');ora.outFormat=ora.OUT_FORMAT_OBJECT;ora.fetchAsString=[ora.CLOB];
readline.createInterface({input:process.stdin,terminal:false}).once('line',async line=>{
 let cfg,c,watch,watchTimer,deadlineTimer,monitoring,secret='',out={startedAt:new Date().toISOString()};
 process.on('message',async m=>{if(m?.cancel&&c)try{await c.break();}catch{}});
 const save=()=>fs.writeFileSync(cfg.outputPath,JSON.stringify(out,null,2));
 try{
  cfg=JSON.parse(line);secret=cfg.password;const credentials={user:cfg.user,password:secret,connectString:cfg.connectString};c=await ora.getConnection(credentials);watch=await ora.getConnection(credentials);c.callTimeout=cfg.timeoutMs||600000;watch.callTimeout=10000;
  const q=async(sql,b={})=>(await c.execute(sql,b,{maxRows:2000})).rows;
  deadlineTimer=setTimeout(()=>{out.protocolError='CLIENT_DEADLINE_EXCEEDED';c.break().catch(()=>{});},cfg.timeoutMs||600000);
  out.question=cfg.question;out.conversation_id=cfg.conversation_id;out.client_turn_id=cfg.client_turn_id;save();
  watchTimer=setInterval(()=>{if(monitoring)return;monitoring=(async()=>{
   const r=(await watch.execute('select request_id,state,flow_steps,execution_conversation_id from POC_V2_RUNS where conversation_id=:c and client_turn_id=:t',{c:cfg.conversation_id,t:cfg.client_turn_id})).rows[0];
   if(!r)return;out.live=r;
   const h=(await watch.execute('select t.* from user_ai_agent_task_history t join user_ai_agent_team_history h on h.team_exec_id=t.team_exec_id where h.conversation_id=:c order by t.task_order',{c:r.EXECUTION_CONVERSATION_ID})).rows;
   out.liveHistory=h;save();
   const bad=h.find(t=>t.TASK_ORDER>0&&t.STATE==='RUNNING'&&t.INPUT==null&&Date.now()-Date.parse(t.START_DATE)>20000);
   if(bad){out.protocolError='NULL_WORKER_INPUT';await c.break();}
  })().catch(e=>{out.monitorError=String(e.message);}).finally(()=>{monitoring=null;});},3000);
  const raw=(await q('select POC_V2_GATE.run(:q,:c,:t) response from dual',{q:cfg.question,c:cfg.conversation_id,t:cfg.client_turn_id}))[0].RESPONSE;
  out.response=JSON.parse(raw);
  out.audit=(await q('select * from POC_V2_RUNS where conversation_id=:c and client_turn_id=:t',{c:cfg.conversation_id,t:cfg.client_turn_id}))[0];
  if(out.audit){out.events=JSON.parse(out.audit.EVENTS_JSON);out.executions=await q('select * from POC_V2_EXECS where request_id=:id order by round_no',{id:out.audit.REQUEST_ID});out.history=out.executions.flatMap(e=>JSON.parse(e.TASK_HISTORY_JSON||'[]'));}
  save();assert.equal(out.response.status,'succeeded',JSON.stringify(out.response));
  assert.equal(out.response.report,out.audit.REPORT,'사용자 응답은 저장 보고서와 문자 단위로 동일해야 함');
  assert.equal(out.audit.REVISION,out.audit.REPORT_REVISION);assert.equal(out.audit.SQL_TEXT,out.audit.APPROVED_SQL);
  assert.equal(out.audit.ORIGINAL_QUESTION,cfg.question);
  const ordered=cfg.noExecution?['REQUEST_CREATED','STANDARDIZE','SHOWSQL','PRE_REVIEW','FINAL_REPORT']:['REQUEST_CREATED','STANDARDIZE','SHOWSQL','PRE_REVIEW','EXECUTE_SAME_SQL','POST_REVIEW','FINAL_REPORT'];
  let ix=-1;for(const step of ordered){const next=out.events.findIndex((e,i)=>i>ix&&e.step===step);assert.ok(next>ix,'상태 전이 누락/역전: '+step);ix=next;}
  if(cfg.noExecution){assert.equal(out.audit.RESULT_JSON,null);assert.equal(out.audit.EXECUTION_ATTEMPTS,0);assert.ok(!('result' in out.response));}
  else{
   out.reference=(await q(cfg.referenceSql)).map(r=>Object.fromEntries(Object.entries(r).map(([k,v])=>[k.toLowerCase(),v])));
   assert.deepEqual(out.response.result.rows,out.reference);assert.deepEqual(JSON.parse(out.audit.RESULT_JSON).rows,out.reference);
   assert.equal(out.audit.EXECUTED_SQL,out.audit.SQL_TEXT);assert.equal(out.audit.EXECUTION_ATTEMPTS,1);
   assert.equal(out.events.filter(e=>e.step==='EXECUTE_SAME_SQL').length,1);
  }
  for(const name of ['POC_V2_SUPERVISOR','POC_V2_STANDARD','POC_V2_QUERY','POC_V2_REVIEW'])assert.ok(out.history.some(h=>h.AGENT_NAME===name),'실제 Agent 이력 누락: '+name);
  for(const h of out.history.filter(h=>h.TASK_ORDER>0))assert.equal(h.INPUT,out.audit.REQUEST_ID,'위임 입력은 요청 ID 문자열 하나여야 함');
  out.pass=true;
 }catch(e){out.pass=false;out.error=String(e.message).split(secret||'\0').join('[redacted]');if(watch&&out.live)try{await watch.execute('select POC_V2_CANCEL_FN(:id,1) r from dual',{id:out.live.REQUEST_ID});}catch(err){out.cancelError=String(err.message);}}
 finally{if(deadlineTimer)clearTimeout(deadlineTimer);if(watchTimer)clearInterval(watchTimer);if(monitoring)await monitoring;out.finishedAt=new Date().toISOString();out.elapsedMs=Date.parse(out.finishedAt)-Date.parse(out.startedAt);if(cfg)save();for(const conn of [c,watch])if(conn)try{await conn.close();}catch{}process.exit(0);}
});
