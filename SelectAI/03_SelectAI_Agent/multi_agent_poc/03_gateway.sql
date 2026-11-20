-- 공개 진입점 POC_V2_GATE와 Worker Tool 어댑터 3개.
-- run/resume에서 Native Supervisor를 호출하고, dispatch는 저장 상태에 맞는 업무 API만 허용한다. public_result는 승인된 저장 결과만 공개한다.

CREATE OR REPLACE PACKAGE POC_V2_GATE AUTHID CURRENT_USER AS
 -- 공개 API: 요청 ID·revision·다음 작업·실제 Human 후보를 포함하는 제어 계약을 만든다.
 FUNCTION status(p_request_id VARCHAR2,p_error VARCHAR2 DEFAULT NULL) RETURN CLOB;
 -- 공개 API: Worker와 저장 상태가 맞을 때만 업무 API를 호출한다. 잘못된 순서와 늦은 호출은 차단한다.
 FUNCTION dispatch(p_worker VARCHAR2,p_request_id VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB;
 -- 공개 API: Native Final Answer를 신뢰하지 않고 저장된 승인·실행 SQL, 검토 계약, 보고서 버전을 모두 확인한 뒤 공개한다.
 FUNCTION public_result(p_request_id VARCHAR2,p_revision NUMBER) RETURN CLOB;
 -- 공개 API: 새 사용자 turn을 초기화하고 중복/실행 중 요청을 구별한 뒤 Native 제어 루프에 진입한다.
 FUNCTION run(p_question VARCHAR2,p_conversation_id VARCHAR2,p_client_turn_id VARCHAR2) RETURN CLOB;
 -- 공개 API: 실제 사용자 답변을 코드에서 검증·저장한 뒤 새 revision으로 Native 흐름을 재개한다.
 FUNCTION resume(p_request_id VARCHAR2,p_revision NUMBER,p_human_answer VARCHAR2) RETURN CLOB;
END;
/
CREATE OR REPLACE PACKAGE BODY POC_V2_GATE AS
 -- 진입/Native 실행과 종료를 요청 이벤트에 기록한다.
 PROCEDURE add_event(p_id VARCHAR2,p_step VARCHAR2,p_detail VARCHAR2) IS
  t CLOB;a JSON_ARRAY_T;o JSON_OBJECT_T:=JSON_OBJECT_T();
 BEGIN
  SELECT events_json INTO t FROM POC_V2_RUNS WHERE request_id=p_id;
  a:=JSON_ARRAY_T.parse(t);o.put('step',p_step);o.put('detail',p_detail);o.put('at',TO_CHAR(SYSTIMESTAMP,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM'));a.append(o);
  t:=a.to_clob();UPDATE POC_V2_RUNS SET events_json=t,updated_at=SYSTIMESTAMP WHERE request_id=p_id;
 END;
 -- Native state_variables의 명시적 요청 포인터를 읽는다. 대화 이력에서 현재 요청을 추측하지 않는다.
 FUNCTION runtime_value(p_name VARCHAR2) RETURN VARCHAR2 IS v CLOB;
 BEGIN v:=DBMS_CLOUD_AI_AGENT.GET_VARIABLE(namespace=>'state_variables',name=>p_name);RETURN DBMS_LOB.SUBSTR(v,200,1);
 EXCEPTION WHEN OTHERS THEN RETURN NULL;END;
 -- 업무 결과 0건과 내부 오류를 혼동하지 않는 제어 JSON을 반환한다.
 FUNCTION error_result(p_code VARCHAR2) RETURN CLOB IS o JSON_OBJECT_T:=JSON_OBJECT_T();
 BEGIN o.put('protocol_version',2);o.put('status','error');o.put('error_code',p_code);o.put('business_result_available',FALSE);RETURN o.to_clob();END;
 -- 저장 상태에서 허용되는 다음 Worker를 계산한다.
 FUNCTION next_worker(r POC_V2_RUNS%ROWTYPE) RETURN VARCHAR2 IS
 BEGIN
  RETURN CASE WHEN r.state='NEW' THEN 'STANDARD'
   WHEN r.state IN ('STANDARDIZED','PREPARE_FAILED','PRECHECK_FAILED','EXECUTE_FAILED','PRECHECKED','RESULT_REVIEWED') THEN 'QUERY'
   WHEN r.state IN ('SQL_GENERATED','EXECUTED','POSTCHECK_FAILED') THEN 'REVIEW'
   WHEN r.state='NEEDS_CLARIFICATION' AND JSON_VALUE(r.context_json,'$.product_candidates.status')='AMBIGUOUS' THEN 'STANDARD'
   WHEN r.state='NEEDS_CLARIFICATION' THEN 'QUERY' ELSE 'NONE' END;
 END;
 -- 요청 ID·revision·다음 작업·실제 Human 후보를 포함하는 제어 계약을 만든다.
 FUNCTION status(p_request_id VARCHAR2,p_error VARCHAR2 DEFAULT NULL) RETURN CLOB IS
  r POC_V2_RUNS%ROWTYPE;o JSON_OBJECT_T:=JSON_OBJECT_T();w VARCHAR2(20);a JSON_ARRAY_T:=JSON_ARRAY_T();ctx JSON_OBJECT_T;p JSON_OBJECT_T;src JSON_ARRAY_T;item JSON_OBJECT_T;q VARCHAR2(2000);
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id;w:=next_worker(r);
  o.put('protocol_version',2);o.put('request_id',r.request_id);o.put('revision',r.revision);o.put('state',r.state);
  o.put('status',CASE WHEN r.state='SUCCEEDED' THEN 'complete' WHEN r.state='NEEDS_CLARIFICATION' THEN 'needs_human' WHEN w='NONE' THEN 'stopped' WHEN p_error IS NOT NULL THEN 'blocked' ELSE 'ready' END);
  o.put('next_agent',CASE WHEN w='NONE' THEN 'NONE' ELSE 'POC_V2_'||w END);
  o.put('next_task',CASE WHEN w='NONE' THEN 'NONE' WHEN r.state='NEEDS_CLARIFICATION' THEN 'POC_V2_'||w||'_HUMAN_TASK' ELSE 'POC_V2_'||w||'_TASK' END);
  o.put('operation',CASE WHEN r.state='NEW' THEN 'STANDARDIZE' WHEN r.state IN ('SQL_GENERATED','EXECUTED','POSTCHECK_FAILED') THEN 'REVIEW' WHEN r.state='PRECHECKED' AND r.execute_allowed='Y' THEN 'EXECUTE' WHEN r.state IN ('PRECHECKED','RESULT_REVIEWED') THEN 'REPORT' WHEN r.state='NEEDS_CLARIFICATION' THEN 'ASK_HUMAN' WHEN w='QUERY' THEN 'PREPARE' ELSE 'STOP' END);
  o.put('flow_steps',r.flow_steps);o.put('needs_human',r.state='NEEDS_CLARIFICATION');o.put('business_result_available',r.state='SUCCEEDED');
  IF p_error IS NOT NULL THEN o.put('error_code',p_error);END IF;
  IF r.state='NEEDS_CLARIFICATION' THEN
   ctx:=JSON_OBJECT_T.parse(r.context_json);
   IF ctx.has('product_candidates') AND ctx.get_object('product_candidates').get_string('status')='AMBIGUOUS' THEN
    p:=ctx.get_object('product_candidates');src:=p.get_array('matches');o.put('candidate_count',p.get_number('match_count'));o.put('candidates_truncated',p.get_boolean('truncated'));
    FOR i IN 0..src.get_size()-1 LOOP DECLARE x JSON_OBJECT_T:=TREAT(src.get(i) AS JSON_OBJECT_T);pid NUMBER:=x.get_number('prod_id');label VARCHAR2(400);BEGIN SELECT ko_name INTO label FROM POC_STD_VALUE WHERE domain_key='product' AND value_key=TO_CHAR(pid);item:=JSON_OBJECT_T();item.put('product_id',pid);item.put('product_name',x.get_string('prod_name'));item.put('display_name',label);a.append(item);END;END LOOP;
    q:='표시된 후보에서 조회할 상품 ID 하나를 선택해 주세요.';IF p.get_boolean('truncated') THEN q:=q||' 전체 '||p.get_number('match_count')||'개 중 일부를 표시했습니다. 원하는 상품이 없으면 정확한 상품명으로 새 질문을 해 주세요.';END IF;
   ELSE q:='조회 목적이나 조건을 확인해 주세요.';
    IF r.requirements_json IS NOT NULL THEN q:=q||' '||DBMS_LOB.SUBSTR(JSON_QUERY(r.requirements_json,'$.unresolved_items' RETURNING CLOB),1500,1);END IF;
   END IF;
   o.put('question',q);o.put('candidates',a);
  END IF;
  RETURN o.to_clob();
 EXCEPTION WHEN NO_DATA_FOUND THEN RETURN error_result('REQUEST_NOT_INITIALIZED');END;
 -- 독립 트랜잭션에서 요청 활성 여부·revision·단계 예산·deadline을 검사하고 호출 수를 기록한다.
 FUNCTION claim_step(p_id VARCHAR2,p_revision NUMBER,p_worker VARCHAR2,p_native BOOLEAN) RETURN BOOLEAN IS
  PRAGMA AUTONOMOUS_TRANSACTION;r POC_V2_RUNS%ROWTYPE;
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_id FOR UPDATE NOWAIT;
  IF r.revision<>p_revision THEN ROLLBACK;RETURN FALSE;END IF;
  IF p_native AND r.runner_active<>'Y' THEN ROLLBACK;RETURN FALSE;END IF;
  IF r.state IN ('SUCCEEDED','FAILED','UNSUPPORTED') THEN COMMIT;RETURN TRUE;END IF;
  IF r.deadline_at<SYSTIMESTAMP OR r.flow_steps>=r.max_steps THEN
   UPDATE POC_V2_RUNS SET state='FAILED',last_error='FLOW_BUDGET_EXCEEDED' WHERE request_id=p_id;
   add_event(p_id,'FLOW_STOPPED','작업 수 또는 전체 deadline 초과');COMMIT;RETURN FALSE;
  END IF;
  UPDATE POC_V2_RUNS SET flow_steps=flow_steps+1 WHERE request_id=p_id;
  add_event(p_id,'TOOL_CALLED',p_worker||'; revision='||p_revision);COMMIT;RETURN TRUE;
 EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;END;
 -- Worker와 저장 상태가 맞을 때만 업무 API를 호출한다. 잘못된 순서와 늦은 호출은 차단한다.
 FUNCTION dispatch(p_worker VARCHAR2,p_request_id VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB IS
  id VARCHAR2(32);bound_id VARCHAR2(200):=runtime_value('request_id');rev NUMBER;bound_rev VARCHAR2(200):=runtime_value('request_revision');r POC_V2_RUNS%ROWTYPE;v CLOB;w VARCHAR2(20);
 BEGIN
  IF bound_id IS NOT NULL AND p_request_id<>bound_id THEN RETURN error_result('REQUEST_ID_MISMATCH');END IF;
  id:=NVL(bound_id,p_request_id);
  IF id IS NULL OR NOT REGEXP_LIKE(id,'^[0-9A-F]{32}$') THEN RETURN error_result('REQUEST_ID_REQUIRED');END IF;
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=id;
  rev:=COALESCE(p_revision,TO_NUMBER(bound_rev),r.revision);
  IF rev<>r.revision THEN RETURN status(id,'STALE_REVISION');END IF;
  IF NOT claim_step(id,rev,p_worker,bound_id IS NOT NULL) THEN RETURN status(id,'REQUEST_NOT_ACTIVE_OR_BUDGET_EXCEEDED');END IF;
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=id;w:=next_worker(r);
  IF r.state IN ('NEEDS_CLARIFICATION','SUCCEEDED','FAILED','UNSUPPORTED') THEN RETURN status(id);END IF;
  IF p_worker<>w THEN RETURN status(id,'WRONG_WORKER');END IF;
  IF w='STANDARD' THEN v:=POC_V2_API.standardize(id,rev);
  ELSIF w='REVIEW' THEN v:=POC_V2_API.review(id,rev);
  ELSIF r.state='PRECHECKED' AND r.execute_allowed='Y' THEN v:=POC_V2_API.execute_sql(id,rev);
  ELSIF r.state IN ('PRECHECKED','RESULT_REVIEWED') THEN v:=POC_V2_API.final_report(id,rev);
  ELSIF w='QUERY' THEN v:=POC_V2_API.prepare(id,'AUTO',rev);
  ELSE RETURN status(id,'INVALID_OPERATION');END IF;
  -- Framework의 status/result 래퍼 안에는 이 동일 JSON 계약만 들어간다. 보고서/숫자는 모델에 반환하지 않는다.
  RETURN status(id);
 EXCEPTION WHEN NO_DATA_FOUND THEN RETURN error_result('REQUEST_NOT_INITIALIZED');
 WHEN OTHERS THEN
  IF id IS NOT NULL THEN RETURN status(id,CASE WHEN SQLCODE=-54 THEN 'REQUEST_BUSY' ELSE 'OPERATION_FAILED: '||SUBSTR(SQLERRM,1,800) END);END IF;
  RETURN error_result('INVALID_REQUEST_CONTEXT');END;
 -- Native Final Answer를 신뢰하지 않고 저장된 승인·실행 SQL, 검토 계약, 보고서 버전을 모두 확인한 뒤 공개한다.
 FUNCTION public_result(p_request_id VARCHAR2,p_revision NUMBER) RETURN CLOB IS
  r POC_V2_RUNS%ROWTYPE;o JSON_OBJECT_T;n NUMBER;v CLOB;
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id;
  IF r.revision<>p_revision THEN RETURN error_result('STALE_REVISION');END IF;
  IF r.state='NEEDS_CLARIFICATION' THEN RETURN status(p_request_id);END IF;
  IF r.state<>'SUCCEEDED' THEN o:=JSON_OBJECT_T.parse(status(p_request_id,'WORKFLOW_NOT_VERIFIED'));o.put('status',CASE WHEN r.state='UNSUPPORTED' THEN 'unsupported' ELSE 'failed' END);RETURN o.to_clob();END IF;
  SELECT COUNT(*) INTO n FROM POC_V2_RUNS WHERE request_id=p_request_id AND report_revision=revision AND report IS NOT NULL
   AND approved_revision=revision AND approved_sql_version=sql_version AND approved_sql IS NOT NULL AND sql_text IS NOT NULL
   AND DBMS_LOB.COMPARE(approved_sql,sql_text)=0 AND JSON_VALUE(pre_review_json,'$.approved')='true' AND JSON_VALUE(pre_review_json,'$.validation_contract')='2'
   AND ((requested_action IN ('SHOWSQL','EXPLAINSQL') AND result_json IS NULL AND execution_attempts=0)
    OR (requested_action IN ('RUNSQL','NARRATE') AND executed_revision=revision AND executed_sql_version=sql_version
     AND executed_sql IS NOT NULL AND DBMS_LOB.COMPARE(executed_sql,sql_text)=0 AND result_json IS NOT NULL AND JSON_VALUE(post_review_json,'$.approved')='true' AND JSON_VALUE(post_review_json,'$.validation_contract')='2'));
  IF n<>1 THEN RETURN error_result('FINAL_VALIDATION_FAILED');END IF;
  o:=JSON_OBJECT_T();o.put('protocol_version',2);o.put('status','succeeded');o.put('request_id',r.request_id);o.put('revision',r.revision);o.put('report',r.report);
  IF r.result_json IS NOT NULL THEN o.put('result',JSON_ELEMENT_T.parse(r.result_json));END IF;
  IF r.requested_action IN ('SHOWSQL','EXPLAINSQL') OR JSON_VALUE(r.requirements_json,'$.include_sql')='true' THEN o.put('sql',r.sql_text);END IF;
  RETURN o.to_clob();
 EXCEPTION WHEN NO_DATA_FOUND THEN RETURN error_result('REQUEST_NOT_INITIALIZED');END;
 -- 요청 실행 토큰을 획득하고 업무 요청과 Native 대화 ID를 연결한다.
 PROCEDURE begin_runner(p_id VARCHAR2,p_revision NUMBER,p_resume BOOLEAN,p_token OUT VARCHAR2,p_exec OUT VARCHAR2,p_wait OUT BOOLEAN) IS
  PRAGMA AUTONOMOUS_TRANSACTION;r POC_V2_RUNS%ROWTYPE;t VARCHAR2(100);
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_id FOR UPDATE NOWAIT;
  IF r.revision<>p_revision THEN RAISE_APPLICATION_ERROR(-20402,'STALE_REVISION');END IF;
  IF r.runner_active='Y' THEN RAISE_APPLICATION_ERROR(-20402,'REQUEST_ALREADY_RUNNING');END IF;
  p_wait:=FALSE;p_exec:=r.execution_conversation_id;
  IF p_resume AND p_exec IS NOT NULL THEN
   BEGIN t:=DBMS_CLOUD_AI_AGENT.GET_TEAM_STATE('POC_V2_TEAM',JSON_OBJECT('conversation_id' VALUE p_exec));p_wait:=(t='WAITING_FOR_HUMAN');EXCEPTION WHEN OTHERS THEN p_wait:=FALSE;END;
  END IF;
  IF NOT p_wait THEN p_exec:=DBMS_CLOUD_AI.CREATE_CONVERSATION(attributes=>'{"title":"POC v2 controlled request","conversation_length":30}');END IF;
  p_token:=RAWTOHEX(SYS_GUID());
  UPDATE POC_V2_RUNS SET execution_conversation_id=p_exec,runner_token=p_token,runner_active='Y',deadline_at=SYSTIMESTAMP+INTERVAL '15' MINUTE WHERE request_id=p_id;
  add_event(p_id,'NATIVE_STARTED','revision='||p_revision||'; conversation='||p_exec);COMMIT;
 EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;END;
 -- 동일 토큰의 실행만 종료한다. 완료 근거 없이 Native가 끝났으면 업무 성공으로 간주하지 않는다.
 PROCEDURE end_runner(p_id VARCHAR2,p_token VARCHAR2,p_raw CLOB,p_error VARCHAR2) IS
  PRAGMA AUTONOMOUS_TRANSACTION;r POC_V2_RUNS%ROWTYPE;
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_id FOR UPDATE NOWAIT;
  IF r.runner_token IS NULL OR r.runner_token<>p_token THEN ROLLBACK;RETURN;END IF;
  UPDATE POC_V2_RUNS SET runner_active='N',raw_agent_output=p_raw,last_error=p_error WHERE request_id=p_id;
  IF r.state NOT IN ('SUCCEEDED','NEEDS_CLARIFICATION','UNSUPPORTED','FAILED') THEN
   UPDATE POC_V2_RUNS SET state='FAILED',last_error=NVL(p_error,'NATIVE_FINISHED_WITHOUT_VERIFIED_REPORT') WHERE request_id=p_id;
  END IF;
  add_event(p_id,'NATIVE_RETURNED',CASE WHEN p_error IS NULL THEN 'Native 반환. 사용자 출력은 저장 승인 결과로 별도 검증.' ELSE SUBSTR(p_error,1,1000) END);COMMIT;
 EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;END;
 -- Native 재진입 한도 12회·deadline·토큰을 검사하고 실행 기록을 시작한다.
 PROCEDURE start_round(p_id VARCHAR2,p_revision NUMBER,p_token VARCHAR2,p_cid VARCHAR2,p_round OUT NUMBER) IS
  PRAGMA AUTONOMOUS_TRANSACTION;r POC_V2_RUNS%ROWTYPE;
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_id FOR UPDATE NOWAIT;
  IF r.runner_token IS NULL OR r.runner_token<>p_token OR r.runner_active<>'Y' OR r.revision<>p_revision THEN RAISE_APPLICATION_ERROR(-20402,'REQUEST_NOT_ACTIVE');END IF;
  SELECT COUNT(*)+1 INTO p_round FROM POC_V2_EXECS WHERE request_id=p_id;
  IF p_round>12 OR r.deadline_at<SYSTIMESTAMP THEN
   UPDATE POC_V2_RUNS SET state='FAILED',last_error='NATIVE_ROUND_BUDGET_EXCEEDED' WHERE request_id=p_id;COMMIT;RAISE_APPLICATION_ERROR(-20402,'NATIVE_ROUND_BUDGET_EXCEEDED');
  END IF;
  UPDATE POC_V2_RUNS SET execution_conversation_id=p_cid WHERE request_id=p_id;
  INSERT INTO POC_V2_EXECS(execution_id,request_id,revision,round_no,conversation_id,state_before,steps_before) VALUES(RAWTOHEX(SYS_GUID()),p_id,p_revision,p_round,p_cid,r.state,r.flow_steps);
  add_event(p_id,'NATIVE_ROUND_STARTED','round='||p_round||'; state='||r.state);COMMIT;
 EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;END;
 -- 다음 Native 실행 전에 공개 Task 이력과 Team 상태를 스냅샷으로 보존한다.
 PROCEDURE record_round(p_id VARCHAR2,p_round NUMBER,p_cid VARCHAR2,p_raw CLOB,p_error VARCHAR2) IS
  PRAGMA AUTONOMOUS_TRANSACTION;r POC_V2_RUNS%ROWTYPE;h CLOB;ns VARCHAR2(40);
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_id FOR UPDATE NOWAIT;
  SELECT JSON_ARRAYAGG(JSON_OBJECT(t.* RETURNING CLOB) ORDER BY t.task_order RETURNING CLOB) INTO h FROM user_ai_agent_task_history t JOIN user_ai_agent_team_history x ON x.team_exec_id=t.team_exec_id WHERE x.conversation_id=p_cid;
  BEGIN ns:=DBMS_CLOUD_AI_AGENT.GET_TEAM_STATE('POC_V2_TEAM',JSON_OBJECT('conversation_id' VALUE p_cid));EXCEPTION WHEN OTHERS THEN ns:='UNKNOWN';END;
  UPDATE POC_V2_EXECS SET state_after=r.state,steps_after=r.flow_steps,native_state=ns,raw_output=p_raw,error_message=p_error,task_history_json=h,ended_at=SYSTIMESTAMP WHERE request_id=p_id AND round_no=p_round;
  add_event(p_id,'NATIVE_ROUND_RETURNED','round='||p_round||'; native='||ns||'; authoritative_state='||r.state);COMMIT;
 EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;END;
 -- 저장 상태별로 Native Supervisor/Worker를 재호출한다. 업무 처리를 직접 수행하는 우회 파이프라인은 없다.
 FUNCTION drive(p_id VARCHAR2,p_revision NUMBER,p_resume BOOLEAN,p_answer VARCHAR2) RETURN CLOB IS
  token VARCHAR2(32);cid VARCHAR2(128);waiting BOOLEAN;par JSON_OBJECT_T;sv JSON_OBJECT_T;args JSON_OBJECT_T;control JSON_OBJECT_T;raw_result CLOB;prompt CLOB;err VARCHAR2(2000);r POC_V2_RUNS%ROWTYPE;round_no NUMBER;old_steps NUMBER;stalls NUMBER:=0;iv JSON_OBJECT_T;ns VARCHAR2(40);
 BEGIN
  begin_runner(p_id,p_revision,p_resume,token,cid,waiting);
  LOOP
   SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_id;old_steps:=r.flow_steps;
   EXIT WHEN r.state IN ('SUCCEEDED','FAILED','UNSUPPORTED');
   start_round(p_id,p_revision,token,cid,round_no);
   par:=JSON_OBJECT_T();sv:=JSON_OBJECT_T();par.put('conversation_id',cid);sv.put('request_id',p_id);sv.put('request_revision',TO_CHAR(p_revision));par.put('state_variables',sv);
   control:=JSON_OBJECT_T.parse(status(p_id));iv:=JSON_OBJECT_T();IF control.get_boolean('needs_human') THEN iv.put('human_question',control.get_string('question')||CHR(10)||control.get_array('candidates').to_clob());par.put('instruction_variables',iv);END IF;args:=JSON_OBJECT_T();args.put('agent_name',control.get_string('next_agent'));args.put('task_name',control.get_string('next_task'));args.put('task_input',p_id);
   IF waiting THEN prompt:=p_answer;
   ELSE prompt:=TO_CLOB('For this single round, delegate EXACTLY ONCE using ORA$DELEGATE_TOOL with this exact JSON. All three values are strings and task_input is the request ID only: ')||args.to_clob()||CHR(10)||'After that worker returns, finish this round with DONE. The application controls later workflow stages. Current control record: '||control.to_clob();END IF;
   raw_result:=NULL;err:=NULL;
   BEGIN raw_result:=DBMS_CLOUD_AI_AGENT.RUN_TEAM(team_name=>'POC_V2_TEAM',user_prompt=>prompt,params=>par.to_clob());EXCEPTION WHEN OTHERS THEN IF SQLCODE=-1013 THEN RAISE;END IF;err:=SUBSTR(SQLERRM,1,1800);END;
   record_round(p_id,round_no,cid,raw_result,err);
   SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_id;
   EXIT WHEN r.state IN ('SUCCEEDED','FAILED','UNSUPPORTED');
   IF r.state='NEEDS_CLARIFICATION' THEN SELECT native_state INTO ns FROM POC_V2_EXECS WHERE request_id=p_id AND conversation_id=cid;IF ns='WAITING_FOR_HUMAN' OR control.get_string('operation')='ASK_HUMAN' THEN EXIT;END IF;END IF;
   IF r.flow_steps=old_steps THEN stalls:=stalls+1;ELSE stalls:=0;END IF;
   IF stalls>=2 THEN err:='NATIVE_NO_PROGRESS';EXIT;END IF;
   -- 모든 업무 단계는 Native Supervisor/Worker가 실행한다. 중간 종료 시 승인 상태를 재주입해 제한적으로 재진입한다.
   waiting:=FALSE;cid:=DBMS_CLOUD_AI.CREATE_CONVERSATION(attributes=>'{"title":"POC v2 next native round","conversation_length":30}');
  END LOOP;
  end_runner(p_id,token,raw_result,err);RETURN public_result(p_id,p_revision);
 EXCEPTION WHEN OTHERS THEN
  IF token IS NOT NULL THEN BEGIN end_runner(p_id,token,NULL,SUBSTR(SQLERRM,1,1800));EXCEPTION WHEN OTHERS THEN NULL;END;END IF;
  RETURN error_result('RUNNER_FAILED: '||SUBSTR(SQLERRM,1,800));END;
 -- 새 사용자 turn을 초기화하고 중복/실행 중 요청을 구별한 뒤 Native 제어 루프에 진입한다.
 FUNCTION run(p_question VARCHAR2,p_conversation_id VARCHAR2,p_client_turn_id VARCHAR2) RETURN CLOB IS id VARCHAR2(32);r POC_V2_RUNS%ROWTYPE;o JSON_OBJECT_T;
 BEGIN
  id:=POC_V2_API.start_request(p_question,p_conversation_id,p_client_turn_id);SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=id;
  IF r.runner_active='Y' THEN o:=JSON_OBJECT_T.parse(status(id));o.put('status','running');RETURN o.to_clob();END IF;
  IF r.state<>'NEW' THEN RETURN public_result(id,r.revision);END IF;
  RETURN drive(id,r.revision,FALSE,NULL);
 END;
 -- 실제 사용자 답변을 코드에서 검증·저장한 뒤 새 revision으로 Native 흐름을 재개한다.
 FUNCTION resume(p_request_id VARCHAR2,p_revision NUMBER,p_human_answer VARCHAR2) RETURN CLOB IS v CLOB;r POC_V2_RUNS%ROWTYPE;
 BEGIN
  v:=POC_V2_API.clarify(p_request_id,p_human_answer,p_revision);SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id;
  IF r.state='NEEDS_CLARIFICATION' THEN RETURN status(p_request_id);END IF;
  RETURN drive(p_request_id,r.revision,TRUE,p_human_answer);
 END;
END;
/
CREATE OR REPLACE FUNCTION POC_V2_STANDARD_FN(p_request_id VARCHAR2) RETURN CLOB AUTHID CURRENT_USER IS
BEGIN RETURN POC_V2_GATE.dispatch('STANDARD',p_request_id);END;
/
CREATE OR REPLACE FUNCTION POC_V2_QUERY_FN(p_request_id VARCHAR2) RETURN CLOB AUTHID CURRENT_USER IS
BEGIN RETURN POC_V2_GATE.dispatch('QUERY',p_request_id);END;
/
CREATE OR REPLACE FUNCTION POC_V2_REVIEW_FN(p_request_id VARCHAR2) RETURN CLOB AUTHID CURRENT_USER IS
BEGIN RETURN POC_V2_GATE.dispatch('REVIEW',p_request_id);END;
/
