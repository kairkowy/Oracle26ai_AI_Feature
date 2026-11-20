'use strict';
const fs=require('node:fs'),assert=require('node:assert/strict'),readline=require('node:readline');
const ora=require(process.argv[2]||'oracledb');ora.outFormat=ora.OUT_FORMAT_OBJECT;ora.fetchAsString=[ora.CLOB];
readline.createInterface({input:process.stdin,terminal:false}).once('line',async line=>{
 let cfg,c,secret='',out={startedAt:new Date().toISOString()};
 const save=()=>fs.writeFileSync(cfg.outputPath,JSON.stringify(out,null,2));
 try{
  cfg=JSON.parse(line);secret=cfg.password;c=await ora.getConnection({user:cfg.user,password:secret,connectString:cfg.connectString});c.callTimeout=600000;
  process.on('message',async m=>{if(m?.cancel)try{await c.break();}catch{}});
  const q=async(sql,b={})=>(await c.execute(sql,b,{maxRows:2000})).rows;
  const question='Team shirt의 상품 ID와 상품명과 정가를 조회해줘.';out.question=question;save();
  out.pending=JSON.parse((await q('select POC_V2_GATE.run(:q,:c,:t) r from dual',{q:question,c:cfg.conversation_id,t:'human-turn'}))[0].R);save();
  assert.equal(out.pending.status,'needs_human');assert.ok(out.pending.candidates.length>1);
  const id=out.pending.request_id;
  out.before=(await q('select * from POC_V2_RUNS where request_id=:id',{id}))[0];
  out.nativeWaitState=(await q('select DBMS_CLOUD_AI_AGENT.GET_TEAM_STATE(:t,:p) s from dual',{t:'POC_V2_TEAM',p:JSON.stringify({conversation_id:out.before.EXECUTION_CONVERSATION_ID})}))[0].S;save();
  await assert.rejects(()=>q('select POC_V2_GATE.resume(:id,1,:a) r from dual',{id,a:'99999999'}));
  assert.equal((await q('select revision from POC_V2_RUNS where request_id=:id',{id}))[0].REVISION,1);
  // 자동 시험의 사용자 역할 입력. 모델이 만든 답변이 아닌 별도 진입 API 호출이다.
  const chosen=out.pending.candidates[1];out.simulatedHumanChoice=chosen;save();
  out.response=JSON.parse((await q('select POC_V2_GATE.resume(:id,1,:a) r from dual',{id,a:String(chosen.product_id)}))[0].R);
  out.audit=(await q('select * from POC_V2_RUNS where request_id=:id',{id}))[0];
  out.executions=await q('select * from POC_V2_EXECS where request_id=:id order by round_no',{id});save();
  assert.equal(out.response.status,'succeeded',JSON.stringify(out.response));assert.equal(out.response.request_id,id);assert.equal(out.response.revision,2);
  assert.equal(out.response.report,out.audit.REPORT);assert.equal(out.audit.ORIGINAL_QUESTION,question);
  out.reference=(await q('select prod_id product_id,prod_name product_name,prod_list_price list_price from products where prod_id=:id',{id:chosen.product_id})).map(r=>Object.fromEntries(Object.entries(r).map(([k,v])=>[k.toLowerCase(),v])));
  assert.deepEqual(out.response.result.rows,out.reference);out.referenceDisplayName=(await q("select ko_name from POC_STD_VALUE where domain_key='product' and value_key=:id",{id:String(chosen.product_id)}))[0].KO_NAME;assert.equal(chosen.display_name,out.referenceDisplayName);assert.ok(out.response.report.includes(String(chosen.product_id)));assert.equal(out.audit.APPROVED_REVISION,2);assert.equal(out.audit.EXECUTED_REVISION,2);assert.equal(out.audit.EXECUTION_ATTEMPTS,1);
  const events=JSON.parse(out.audit.EVENTS_JSON);assert.equal(events.filter(e=>e.step==='HUMAN_CONFIRMED').length,1);assert.equal(events.filter(e=>e.step==='EXECUTE_SAME_SQL').length,1);
  out.apiFlowPass=true;out.nativeWaitObserved=out.nativeWaitState==='WAITING_FOR_HUMAN';out.pass=out.apiFlowPass&&out.nativeWaitObserved;
  if(!out.nativeWaitObserved)out.error='사용자 확인 API 흐름은 완료했으나 Native WAITING_FOR_HUMAN은 관찰되지 않음';
 }catch(e){out.pass=false;out.error=String(e.message).split(secret||'\0').join('[redacted]');}
 finally{out.finishedAt=new Date().toISOString();out.elapsedMs=Date.parse(out.finishedAt)-Date.parse(out.startedAt);if(cfg)save();if(c)try{await c.close();}catch{}process.exit(0);}
});
