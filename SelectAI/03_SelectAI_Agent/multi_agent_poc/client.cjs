'use strict';
// 표준입력 JSON으로 접속 정보와 요청을 받는다. 자격 증명을 파일/명령 인수에 쓰지 않는다.
const ora=require(process.argv[2]||'oracledb'),readline=require('node:readline');
ora.outFormat=ora.OUT_FORMAT_OBJECT;ora.fetchAsString=[ora.CLOB];
readline.createInterface({input:process.stdin,terminal:false}).once('line',async line=>{
 let cfg,c,watch,timer,deadlineTimer,monitoring,request,protocolError;
 try{
  cfg=JSON.parse(line);const credentials={user:cfg.user,password:cfg.password,connectString:cfg.connectString};
  c=await ora.getConnection(credentials);watch=await ora.getConnection(credentials);c.callTimeout=cfg.timeoutMs||600000;watch.callTimeout=10000;
  process.on('SIGINT',()=>{if(c)c.break().catch(()=>{});});
  deadlineTimer=setTimeout(()=>{protocolError='CLIENT_DEADLINE_EXCEEDED';c.break().catch(()=>{});},cfg.timeoutMs||600000);
  timer=setInterval(()=>{if(monitoring)return;monitoring=(async()=>{
   const rows=(await watch.execute(cfg.request_id?'select * from POC_V2_RUNS where request_id=:id':'select * from POC_V2_RUNS where conversation_id=:c and client_turn_id=:t',cfg.request_id?{id:cfg.request_id}:{c:cfg.conversation_id,t:cfg.client_turn_id})).rows;
   request=rows[0];if(!request||request.RUNNER_ACTIVE!=='Y')return;
   const tasks=(await watch.execute("select t.input,t.start_date from user_ai_agent_task_history t join user_ai_agent_team_history h on h.team_exec_id=t.team_exec_id where h.conversation_id=:c and t.task_order>0 and t.state='RUNNING'",{c:request.EXECUTION_CONVERSATION_ID})).rows;
   if(tasks.some(t=>t.INPUT==null&&Date.now()-Date.parse(t.START_DATE)>20000)){protocolError='NULL_WORKER_INPUT';await c.break();}
  })().catch(()=>{}).finally(()=>{monitoring=null;});},3000);
  const sql=cfg.request_id?'select POC_V2_GATE.resume(:id,:rev,:a) response from dual':'select POC_V2_GATE.run(:q,:c,:t) response from dual';
  const binds=cfg.request_id?{id:cfg.request_id,rev:cfg.revision,a:cfg.human_answer}:{q:cfg.question,c:cfg.conversation_id,t:cfg.client_turn_id};
  const response=(await c.execute(sql,binds)).rows[0].RESPONSE;
  process.stdout.write(JSON.stringify(JSON.parse(response),null,2)+'\n');
 }catch(e){
  if(watch&&request&&(protocolError||/NJS-123|DPI-1067|ORA-01013/.test(e.message)))try{await watch.execute('select POC_V2_CANCEL_FN(:id,:rev) r from dual',{id:request.REQUEST_ID,rev:request.REVISION});}catch{}
  process.stdout.write(JSON.stringify({status:'error',error_code:protocolError||'REQUEST_FAILED',message:String(e.message).split(cfg?.password||'\0').join('[redacted]')})+'\n');
  process.exitCode=1;
 }finally{if(deadlineTimer)clearTimeout(deadlineTimer);if(timer)clearInterval(timer);if(monitoring)await monitoring;for(const conn of [c,watch])if(conn)try{await conn.close();}catch{}}
});
