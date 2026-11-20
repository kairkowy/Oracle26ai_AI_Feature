-- 업무 처리 패키지 POC_V2_API. 표준화 → 요구 해석/SQL 생성 → 사전 검토 → 동일 SQL 실행 → 사후 검토 → 보고.
-- 단계별 상태·revision을 검사하고 독립 트랜잭션에서 저장한다. 모델 문장이 아닌 저장된 SQL과 원시 행이 실행/보고의 근거다.

CREATE OR REPLACE PACKAGE POC_V2_API AUTHID CURRENT_USER AS
 -- 공개 API: LLM 호출 전에 요청을 영속화한다. 동일 turn 재전송만 멱등 처리하고 다른 원문 충돌은 거절한다.
 FUNCTION start_request(p_question VARCHAR2,p_conversation_id VARCHAR2,p_client_turn_id VARCHAR2) RETURN VARCHAR2;
 -- 공개 API: 원문을 사전/실제 상품 후보에 연결해 STANDARDIZED 또는 NEEDS_CLARIFICATION으로 전이한다.
 FUNCTION standardize(p_request_id VARCHAR2,p_revision NUMBER) RETURN CLOB;
 -- 공개 API: 실제 후보 ID를 검증하고 revision을 올리며 이전 승인·SQL 결과를 무효화한다.
 FUNCTION clarify(p_request_id VARCHAR2,p_answer VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB;
 -- 공개 API: 요구 JSON을 만든 뒤 showsql로 SQL만 생성한다. 원문 실행 금지는 후단에서도 고정하고 생성 시도 한도를 적용한다.
 FUNCTION prepare(p_request_id VARCHAR2,p_action VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB;
 -- 공개 API: 실행 전에는 SQL/집계 의미를, 실행 후에는 원시 행/고유 키/출력 형태를 검토한다. 승인 계약 버전을 저장한다.
 FUNCTION review(p_request_id VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB;
 -- 공개 API: 행 잠금 아래 승인 revision·SQL version·SQL CLOB 전체를 비교한 뒤 그 SQL을 DBMS_SQL로 한 번 실행한다.
 FUNCTION execute_sql(p_request_id VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB;
 -- 공개 API: 검토된 저장 결과를 기존 한글 표시 규칙으로 렌더링한다. 최종 보고서와 report_revision을 함께 저장한다.
 FUNCTION final_report(p_request_id VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB;
 -- 공개 API: 저장된 업무 상태를 진단 JSON으로 읽는다. 최종 공개 검증은 Gate에서 별도 수행한다.
 FUNCTION inspect(p_request_id VARCHAR2) RETURN CLOB;
END;
/
CREATE OR REPLACE PACKAGE BODY POC_V2_API AS
 -- 업무 오류를 일관된 Oracle 오류 코드로 반환한다.
 PROCEDURE fail(p_text VARCHAR2) IS BEGIN RAISE_APPLICATION_ERROR(-20301,SUBSTR(p_text,1,1800)); END;
 -- 기존 정책 테이블에서 한도 값을 읽는다.
 FUNCTION policy(p_key VARCHAR2) RETURN NUMBER IS v NUMBER;
 BEGIN SELECT number_value INTO v FROM POC_AI_POLICY WHERE policy_key=p_key; RETURN v; END;
 -- 32KB 초과도 잘리지 않도록 CLOB 전체에서 모델 JSON을 파싱한다.
 FUNCTION obj(p_text CLOB) RETURN JSON_OBJECT_T IS
  v CLOB; a INTEGER; b INTEGER; o JSON_OBJECT_T;
 BEGIN
  BEGIN RETURN JSON_OBJECT_T.parse(p_text); EXCEPTION WHEN OTHERS THEN NULL; END;
  a:=INSTR(p_text,'{');b:=INSTR(p_text,'}',-1);
  IF a=0 OR b<a THEN fail('JSON 응답이 필요합니다.');END IF;
  DBMS_LOB.CREATETEMPORARY(v,TRUE);DBMS_LOB.COPY(v,p_text,b-a+1,1,a);
  o:=JSON_OBJECT_T.parse(v);DBMS_LOB.FREETEMPORARY(v);RETURN o;
 EXCEPTION WHEN OTHERS THEN IF DBMS_LOB.ISTEMPORARY(v)=1 THEN DBMS_LOB.FREETEMPORARY(v);END IF;RAISE;END;
 -- 사용자 확인 이전의 오래된 revision 호출을 거절한다.
 PROCEDURE check_revision(p_actual NUMBER,p_expected NUMBER) IS
 BEGIN IF p_expected IS NOT NULL AND p_actual<>p_expected THEN fail('STALE_REVISION');END IF;END;
 -- Tool 모델 호출마다 별도 대화를 만들어 이전 추론의 오염을 줄이고 원래 세션 대화를 복원한다.
 FUNCTION ask(p_text CLOB,p_action VARCHAR2 DEFAULT 'chat',p_sql_profile VARCHAR2 DEFAULT 'POC_V2_SQL_PROFILE') RETURN CLOB IS
  prev VARCHAR2(128):=DBMS_CLOUD_AI.GET_CONVERSATION_ID(); cid VARCHAR2(128); v CLOB; par JSON_OBJECT_T:=JSON_OBJECT_T();
  PROCEDURE restore IS BEGIN IF prev IS NULL THEN DBMS_CLOUD_AI.CLEAR_CONVERSATION_ID; ELSE DBMS_CLOUD_AI.SET_CONVERSATION_ID(prev); END IF; END;
 BEGIN
  cid:=DBMS_CLOUD_AI.CREATE_CONVERSATION(attributes=>'{"title":"POC supervised isolated tool","conversation_length":1}');
  DBMS_CLOUD_AI.SET_CONVERSATION_ID(cid); par.put('conversation_id',cid);
  v:=DBMS_CLOUD_AI.GENERATE(prompt=>p_text,profile_name=>CASE WHEN LOWER(p_action)='showsql' THEN p_sql_profile ELSE 'POC_AI_PROFILE' END,action=>p_action,params=>par.to_clob()); restore; RETURN v;
 EXCEPTION WHEN OTHERS THEN restore; RAISE; END;
 -- 업무 요청의 단계와 시간을 저장한다.
 PROCEDURE event(p_id VARCHAR2,p_step VARCHAR2,p_detail VARCHAR2) IS
  a JSON_ARRAY_T; o JSON_OBJECT_T:=JSON_OBJECT_T(); t CLOB;
 BEGIN
  SELECT events_json INTO t FROM POC_V2_RUNS WHERE request_id=p_id FOR UPDATE NOWAIT;
  a:=JSON_ARRAY_T.parse(t); o.put('step',p_step); o.put('detail',p_detail); o.put('at',TO_CHAR(SYSTIMESTAMP,'YYYY-MM-DD"T"HH24:MI:SS.FF3TZH:TZM')); a.append(o);
  t:=a.to_clob();
  UPDATE POC_V2_RUNS SET events_json=t,updated_at=SYSTIMESTAMP WHERE request_id=p_id;
 END;
 -- 기존 데이터셋·필드·허용 조인 메타데이터를 요구 해석/생성 문맥으로 구성한다.
 FUNCTION catalog RETURN CLOB IS
  v CLOB;
 BEGIN
  SELECT JSON_OBJECT('fields' VALUE (SELECT JSON_ARRAYAGG(JSON_OBJECT('key' VALUE field_key,'sql' VALUE CASE WHEN field_key='currency' THEN '''USD''' ELSE sql_expression END,'type' VALUE data_type,'label' VALUE label_ko,'meaning' VALUE description) RETURNING CLOB) FROM POC_AI_FIELD) FORMAT JSON,
  'datasets' VALUE (SELECT JSON_ARRAYAGG(JSON_OBJECT('key' VALUE dataset_key,'from' VALUE base_from,'meaning' VALUE description) RETURNING CLOB) FROM POC_AI_DATASET) FORMAT JSON,
  'joins' VALUE (SELECT JSON_ARRAYAGG(JSON_OBJECT('dataset' VALUE dataset_key,'sql' VALUE join_sql) RETURNING CLOB) FROM POC_AI_JOIN WHERE INSTR(UPPER(join_sql),'POC_SETTING')=0) FORMAT JSON RETURNING CLOB) INTO v FROM dual; RETURN v;
 END;
 -- 의미 요구 추출에서는 SQL 식과 FROM/조인을 제거해 구현 SQL의 모방을 줄인다.
 FUNCTION semantic_context(p_context CLOB) RETURN CLOB IS
  o JSON_OBJECT_T:=JSON_OBJECT_T.parse(p_context); c JSON_OBJECT_T; a JSON_ARRAY_T; item JSON_OBJECT_T;ds JSON_ARRAY_T;
 BEGIN
  c:=o.get_object('catalog');c.remove('joins');ds:=c.get_array('datasets');FOR i IN 0..ds.get_size()-1 LOOP item:=TREAT(ds.get(i) AS JSON_OBJECT_T);item.remove('from');ds.put(i,item,TRUE);END LOOP;c.put('datasets',ds);a:=c.get_array('fields');
  FOR i IN 0..a.get_size()-1 LOOP item:=TREAT(a.get(i) AS JSON_OBJECT_T);item.remove('sql');a.put(i,item,TRUE);END LOOP;
  c.put('fields',a);o.put('catalog',c);RETURN o.to_clob();
 END;
 -- 실제 상품 후보만 Worker에 전달한다. 모호한 후보를 임의 선택하지 않는다.
 FUNCTION product_handoff(p_context CLOB) RETURN CLOB IS
  ctx JSON_OBJECT_T:=JSON_OBJECT_T.parse(p_context); src JSON_OBJECT_T; o JSON_OBJECT_T:=JSON_OBJECT_T(); candidates JSON_ARRAY_T:=JSON_ARRAY_T(); matches JSON_ARRAY_T; item JSON_OBJECT_T; target JSON_OBJECT_T;
 BEGIN
  IF NOT ctx.has('product_candidates') THEN o.put('status','NOT_APPLICABLE');o.put('needs_human',FALSE);RETURN o.to_clob(); END IF;
  src:=ctx.get_object('product_candidates');o.put('status',src.get_string('status'));o.put('candidate_count',src.get_number('match_count'));o.put('truncated',src.get_boolean('truncated'));
  matches:=src.get_array('matches');
  FOR i IN 0..matches.get_size()-1 LOOP item:=TREAT(matches.get(i) AS JSON_OBJECT_T);target:=JSON_OBJECT_T();target.put('product_id',item.get_number('prod_id'));target.put('product_name',item.get_string('prod_name'));target.put('list_price',item.get_number('prod_list_price'));candidates.append(target);END LOOP;
  o.put('candidates',candidates);o.put('needs_human',src.get_string('status')<>'MATCH');
  IF src.get_string('status')='MATCH' THEN o.put('next_step','UNIQUE PRODUCT CONFIRMED. Do not ask human. Return request_id to supervisor for query worker.');
  ELSE o.put('next_step','Show actual candidate IDs and names and ask the user to identify the product.');END IF;
  RETURN o.to_clob();
 END;
 -- 저장된 업무 상태를 진단 JSON으로 읽는다. 최종 공개 검증은 Gate에서 별도 수행한다.
 FUNCTION inspect(p_request_id VARCHAR2) RETURN CLOB IS v CLOB; ctx CLOB; product_info CLOB;
 BEGIN
  SELECT context_json INTO ctx FROM POC_V2_RUNS WHERE request_id=p_request_id;
  product_info:=product_handoff(ctx);
  SELECT JSON_OBJECT('request_id' VALUE request_id,'original_question' VALUE original_question,'question' VALUE effective_question,'state' VALUE state,'requested_action' VALUE requested_action,'execute_allowed' VALUE execute_allowed,
   'generation_attempts' VALUE generation_attempts,'execution_attempts' VALUE execution_attempts,'standard_bindings' VALUE JSON_QUERY(context_json,'$.standard_bindings' RETURNING CLOB) FORMAT JSON,'product_resolution' VALUE product_info FORMAT JSON,'question_hints' VALUE JSON_QUERY(context_json,'$.question_hints' RETURNING CLOB) FORMAT JSON,'requirements' VALUE requirements_json FORMAT JSON,'sql' VALUE sql_text,'columns' VALUE columns_json FORMAT JSON,'pre_review' VALUE pre_review_json FORMAT JSON,'result_summary' VALUE JSON_OBJECT('row_count' VALUE JSON_VALUE(result_json,'$.row_count' RETURNING NUMBER),'truncated' VALUE JSON_VALUE(result_json,'$.truncated'),'fetch_limit' VALUE JSON_VALUE(result_json,'$.fetch_limit' RETURNING NUMBER)),'post_review' VALUE post_review_json FORMAT JSON,'report' VALUE report RETURNING CLOB)
  INTO v FROM POC_V2_RUNS WHERE request_id=p_request_id; RETURN v;
 END;
 -- 기존 표준화 사전과 상품 해소 함수로 질문 문맥을 만들고 통화 가정을 명시한다.
 FUNCTION context_for(p_q VARCHAR2) RETURN CLOB IS o JSON_OBJECT_T:=JSON_OBJECT_T(); scan JSON_OBJECT_T;
 BEGIN
  scan:=JSON_OBJECT_T.parse(POC_STANDARD.scan_question(p_q));
  o.put('standard_bindings',scan);
  IF scan.has('product_term') THEN o.put('product_candidates',JSON_ELEMENT_T.parse(POC_PRODUCT_RESOLVE(scan.get_string('product_term')))); END IF;
  o.put('question_hints',JSON_ELEMENT_T.parse(POC_STANDARD.question_hints(p_q))); o.put('catalog',JSON_ELEMENT_T.parse(catalog)); o.put('currency_assumption','원본 SH에는 통화 컬럼이 없습니다. USD는 POC 가정이며 환율 변환을 하지 않습니다.'); RETURN o.to_clob();
 END;
 -- LLM 호출 전에 요청을 영속화한다. 동일 turn 재전송만 멱등 처리하고 다른 원문 충돌은 거절한다.
 FUNCTION start_request(p_question VARCHAR2,p_conversation_id VARCHAR2,p_client_turn_id VARCHAR2) RETURN VARCHAR2 IS
  PRAGMA AUTONOMOUS_TRANSACTION; id VARCHAR2(32):=RAWTOHEX(SYS_GUID());q VARCHAR2(4000);
 BEGIN
  IF p_question IS NULL OR LENGTH(p_question)>3500 OR p_conversation_id IS NULL OR p_client_turn_id IS NULL THEN fail('질문, conversation_id, client_turn_id가 필요합니다.');END IF;
  INSERT INTO POC_V2_RUNS(request_id,conversation_id,client_turn_id,original_question,effective_question,state)
  VALUES(id,p_conversation_id,p_client_turn_id,p_question,p_question,'NEW');
  event(id,'REQUEST_CREATED','신규 사용자 turn. 동일 문장도 별도 turn이면 신규 요청.');COMMIT;RETURN id;
 EXCEPTION WHEN DUP_VAL_ON_INDEX THEN
  SELECT request_id,original_question INTO id,q FROM POC_V2_RUNS WHERE conversation_id=p_conversation_id AND client_turn_id=p_client_turn_id;
  IF q<>p_question THEN ROLLBACK;fail('IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_QUESTION');END IF;COMMIT;RETURN id;
 WHEN OTHERS THEN ROLLBACK;RAISE;END;
 -- 원문을 사전/실제 상품 후보에 연결해 STANDARDIZED 또는 NEEDS_CLARIFICATION으로 전이한다.
 FUNCTION standardize(p_request_id VARCHAR2,p_revision NUMBER) RETURN CLOB IS
  PRAGMA AUTONOMOUS_TRANSACTION;r POC_V2_RUNS%ROWTYPE;v CLOB;ctx JSON_OBJECT_T;s VARCHAR2(40):='STANDARDIZED';p JSON_OBJECT_T;
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id FOR UPDATE NOWAIT;check_revision(r.revision,p_revision);
  IF r.state<>'NEW' THEN COMMIT;RETURN inspect(p_request_id);END IF;
  v:=context_for(r.effective_question);ctx:=JSON_OBJECT_T.parse(v);
  IF ctx.has('product_candidates') THEN p:=ctx.get_object('product_candidates');IF p.get_string('status')='AMBIGUOUS' THEN s:='NEEDS_CLARIFICATION';END IF;END IF;
  UPDATE POC_V2_RUNS SET state=s,context_json=v WHERE request_id=p_request_id;
  event(p_request_id,'STANDARDIZE','저장 원문으로 재사용 사전·메타데이터·실제 상품 후보 확인');COMMIT;RETURN inspect(p_request_id);
 EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;END;
 -- 실제 후보 ID를 검증하고 revision을 올리며 이전 승인·SQL 결과를 무효화한다.
 FUNCTION clarify(p_request_id VARCHAR2,p_answer VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB IS
  PRAGMA AUTONOMOUS_TRANSACTION;r POC_V2_RUNS%ROWTYPE;q VARCHAR2(4000);v CLOB;ctx JSON_OBJECT_T;p JSON_OBJECT_T;a JSON_ARRAY_T;chosen JSON_OBJECT_T;matches JSON_ARRAY_T:=JSON_ARRAY_T();id NUMBER;s VARCHAR2(40):='STANDARDIZED';bs JSON_OBJECT_T;ba JSON_ARRAY_T;filtered JSON_ARRAY_T:=JSON_ARRAY_T();
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id FOR UPDATE NOWAIT;check_revision(r.revision,p_revision);
  IF r.state<>'NEEDS_CLARIFICATION' OR p_answer IS NULL THEN fail('NO_PENDING_HUMAN_QUESTION');END IF;
  ctx:=JSON_OBJECT_T.parse(r.context_json);
  IF ctx.has('product_candidates') AND ctx.get_object('product_candidates').get_string('status')='AMBIGUOUS' THEN
   IF NOT REGEXP_LIKE(TRIM(p_answer),'^[0-9]+$') THEN fail('CHOOSE_ONE_ACTUAL_PRODUCT_ID');END IF;
   id:=TO_NUMBER(TRIM(p_answer));p:=ctx.get_object('product_candidates');a:=p.get_array('matches');
   FOR i IN 0..a.get_size()-1 LOOP DECLARE x JSON_OBJECT_T:=TREAT(a.get(i) AS JSON_OBJECT_T);BEGIN IF x.get_number('prod_id')=id THEN chosen:=x;END IF;END;END LOOP;
   IF chosen IS NULL THEN fail('PRODUCT_ID_NOT_IN_CANDIDATES');END IF;
   matches.append(chosen);p.put('matches',matches);p.put('status','MATCH');p.put('match_count',1);p.put('truncated',FALSE);ctx.put('product_candidates',p);ctx.put('confirmed_product_id',id);
   bs:=ctx.get_object('standard_bindings');ba:=bs.get_array('bindings');
   FOR i IN 0..ba.get_size()-1 LOOP DECLARE x JSON_OBJECT_T:=TREAT(ba.get(i) AS JSON_OBJECT_T);BEGIN IF x.get_string('domain')<>'product' OR x.get_string('value_key')=TO_CHAR(id) THEN filtered.append(x);END IF;END;END LOOP;
   bs.put('bindings',filtered);ctx.put('standard_bindings',bs);
   q:=r.effective_question||CHR(10)||'사용자가 확정한 상품 ID: '||id;
  ELSE
   q:=r.effective_question||CHR(10)||'사용자 추가 확인: '||p_answer;ctx:=JSON_OBJECT_T.parse(context_for(q));
   IF ctx.has('product_candidates') AND ctx.get_object('product_candidates').get_string('status')='AMBIGUOUS' THEN s:='NEEDS_CLARIFICATION';END IF;
  END IF;
  IF LENGTH(q)>3900 THEN fail('확인 답변을 포함한 질문이 너무 깁니다.');END IF;
  v:=ctx.to_clob();UPDATE POC_V2_RUNS SET effective_question=q,revision=revision+1,state=s,context_json=v,requested_action=NULL,execute_allowed='N',generation_attempts=0,execution_attempts=0,requirements_json=NULL,sql_text=NULL,columns_json=NULL,pre_review_json=NULL,result_json=NULL,post_review_json=NULL,report=NULL,approved_revision=NULL,approved_sql_version=NULL,approved_sql=NULL,executed_revision=NULL,executed_sql_version=NULL,executed_sql=NULL,report_revision=NULL,deadline_at=SYSTIMESTAMP+INTERVAL '15' MINUTE WHERE request_id=p_request_id;
  event(p_request_id,'HUMAN_CONFIRMED','실제 진입 API에 제공된 답변만 반영. 후보 ID 검증 및 승인 무효화.');COMMIT;RETURN inspect(p_request_id);
 EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;END;
 -- 제한된 SELECT 문법만 허용한다. 자유 SQL 검사이며 구조화 계획 컴파일러가 아니다.
 -- 모델이 반환한 컬럼을 등록된 업무 필드 키에 연결한다.
 FUNCTION column_key(p_name VARCHAR2) RETURN VARCHAR2 IS v VARCHAR2(128);
 BEGIN
  SELECT field_key INTO v FROM POC_AI_FIELD WHERE UPPER(field_key)=UPPER(p_name);
  RETURN LOWER(v);
 EXCEPTION WHEN NO_DATA_FOUND THEN
  BEGIN SELECT field_key INTO v FROM POC_AI_FIELD WHERE REGEXP_LIKE(sql_expression,'^[A-Z]+\.'||UPPER(p_name)||'$'); RETURN LOWER(v);
  EXCEPTION WHEN NO_DATA_FOUND OR TOO_MANY_ROWS THEN RETURN LOWER(p_name); END;
 END;
 -- dataset_key·필드 소속·상품 ID·고유 행 키를 메타데이터로 검증한다.
 PROCEDURE normalize_plan(req IN OUT JSON_OBJECT_T,p_context CLOB) IS
  ctx JSON_OBJECT_T:=JSON_OBJECT_T.parse(p_context);pc JSON_OBJECT_T;ma JSON_ARRAY_T;f JSON_OBJECT_T;fa JSON_ARRAY_T;fo JSON_ARRAY_T:=JSON_ARRAY_T();outputs JSON_ARRAY_T:=req.get_array('required_outputs');groups JSON_ARRAY_T:=req.get_array('group_keys');dk VARCHAR2(30):=req.get_string('dataset_key');uk VARCHAR2(30);field VARCHAR2(128);op VARCHAR2(30):='=';n NUMBER;rid NUMBER;entity BOOLEAN:=FALSE;found BOOLEAN:=FALSE;agg BOOLEAN:=FALSE;bindings JSON_ARRAY_T;ids JSON_OBJECT_T:=JSON_OBJECT_T();
  PROCEDURE field_allowed(p_field VARCHAR2) IS c NUMBER;k VARCHAR2(128):=p_field;
  BEGIN
   IF k='product_count' THEN k:='product_id';ELSE k:=REGEXP_REPLACE(k,'_(sum|avg|min|max)$','');END IF;
   SELECT COUNT(*) INTO c FROM POC_AI_DATASET_FIELD WHERE dataset_key=dk AND field_key=k;
   IF c<>1 THEN fail('FIELD_NOT_IN_DATASET: '||p_field);END IF;
  END;
 BEGIN
  IF dk IS NULL THEN fail('DATASET_KEY_REQUIRED');END IF;
  SELECT unique_key_field INTO uk FROM POC_AI_DATASET WHERE dataset_key=dk;
  IF ctx.has('product_candidates') THEN
   pc:=ctx.get_object('product_candidates');ma:=pc.get_array('matches');
   IF pc.get_string('status')='MATCH' AND ma.get_size()=1 THEN
    f:=TREAT(ma.get(0) AS JSON_OBJECT_T);rid:=f.get_number('prod_id');entity:=TRUE;
    bindings:=ctx.get_object('standard_bindings').get_array('bindings');
    FOR i IN 0..bindings.get_size()-1 LOOP f:=TREAT(bindings.get(i) AS JSON_OBJECT_T);IF f.get_string('domain')='product' THEN ids.put(f.get_string('value_key'),TRUE);END IF;END LOOP;
    IF ids.get_size()>1 AND NOT ctx.has('confirmed_product_id') THEN entity:=FALSE;END IF;
   END IF;
  END IF;
  fa:=req.get_array('filters');
  IF fa IS NOT NULL THEN FOR i IN 0..fa.get_size()-1 LOOP
   f:=TREAT(fa.get(i) AS JSON_OBJECT_T);field:=f.get_string('field');
   IF field IN ('product_term','product_name','product_id') AND entity THEN
    op:=NVL(f.get_string('operator'),'=');IF op='!=' THEN op:='<>';END IF;
    IF op NOT IN ('=','<>') THEN fail('UNSUPPORTED_SINGLE_PRODUCT_OPERATOR');END IF;
    f.put('field','product_id');f.put('value',rid);f.put('operator',op);found:=TRUE;
   END IF;
   field_allowed(f.get_string('field'));fo.append(f);
  END LOOP;END IF;
  IF entity AND NOT found THEN f:=JSON_OBJECT_T();f.put('field','product_id');f.put('operator','=');f.put('value',rid);fo.append(f);op:='=';END IF;
  IF entity THEN req.put('resolved_product_id',rid);req.put('resolved_product_operator',op);END IF;
  req.put('filters',fo);
  IF outputs IS NULL OR outputs.get_size()=0 THEN fail('REQUIRED_OUTPUTS_MISSING');END IF;
  FOR i IN 0..outputs.get_size()-1 LOOP field_allowed(outputs.get_string(i));IF REGEXP_LIKE(outputs.get_string(i),'_(sum|avg|min|max)$|^product_count$') THEN agg:=TRUE;END IF;END LOOP;
  IF groups IS NULL THEN fail('GROUP_KEYS_REQUIRED');END IF;
  FOR i IN 0..groups.get_size()-1 LOOP field_allowed(groups.get_string(i));END LOOP;
  IF uk IS NOT NULL AND groups.get_size()=0 AND NOT agg THEN
   found:=FALSE;FOR i IN 0..outputs.get_size()-1 LOOP IF outputs.get_string(i)=uk THEN found:=TRUE;END IF;END LOOP;
   IF NOT found THEN outputs.append(uk);END IF;req.put('required_outputs',outputs);req.put('row_identity_key',uk);
  END IF;
 END;
 -- 제한된 SELECT 허용 규칙과 데이터셋 소스·출력·상품 ID 조건을 검사하고 DBMS_SQL로 파싱/컬럼 기술한다. 완전한 SQL 의미 증명은 아니다.
 PROCEDURE check_sql(p_sql CLOB,p_req CLOB,p_columns OUT CLOB) IS
  s VARCHAR2(32767):=TRIM(DBMS_LOB.SUBSTR(p_sql,32767,1)); t VARCHAR2(32767); token VARCHAR2(128); allowed CLOB; i PLS_INTEGER:=1; c INTEGER; n INTEGER; d DBMS_SQL.DESC_TAB2; a JSON_ARRAY_T:=JSON_ARRAY_T(); req JSON_OBJECT_T:=obj(p_req); outputs JSON_ARRAY_T; present BOOLEAN; groups JSON_ARRAY_T; group_clause VARCHAR2(32767); expr VARCHAR2(1000); pos PLS_INTEGER;dk VARCHAR2(30);source_sql VARCHAR2(32767);dataset_tables VARCHAR2(4000);table_count NUMBER;from_part VARCHAR2(32767);
 BEGIN
  IF DBMS_LOB.GETLENGTH(p_sql)>30000 OR NOT REGEXP_LIKE(s,'^SELECT[[:space:]]','i') THEN fail('단일 SELECT만 지원합니다.'); END IF;
  IF INSTR(s,';')>0 OR INSTR(s,'--')>0 OR INSTR(s,'/*')>0 OR INSTR(s,'@')>0 OR INSTR(s,':')>0 THEN fail('주석·다중 문장·DB link·바인드는 허용하지 않습니다.'); END IF;
  -- 문자열 내부는 토큰 검사에서 제외하고, 식별자는 허용 목록으로 제한한다.
  t:=REGEXP_REPLACE(s,'''(''''|[^''])*''',' ');
  t:=REPLACE(t,'"','');
  IF req.has('confirmed_product_id') AND NOT REGEXP_LIKE(UPPER(t),'P[.]PROD_ID[[:space:]]*=[[:space:]]*'||req.get_number('confirmed_product_id')||'([^0-9]|$)') THEN fail('CONFIRMED_PRODUCT_FILTER_REQUIRED');END IF;
  dk:=req.get_string('dataset_key');IF dk IS NULL THEN fail('DATASET_KEY_REQUIRED');END IF;
  SELECT base_from INTO source_sql FROM POC_AI_DATASET WHERE dataset_key=dk;
  FOR j IN (SELECT join_sql FROM POC_AI_JOIN WHERE dataset_key=dk AND INSTR(UPPER(join_sql),'POC_SETTING')=0) LOOP source_sql:=source_sql||' '||j.join_sql;END LOOP;
  dataset_tables:=',';table_count:=0;
  FOR j IN (SELECT table_name FROM user_tables WHERE table_name IN ('PRODUCTS','SALES','CUSTOMERS','COUNTRIES','TIMES')) LOOP
   IF REGEXP_LIKE(UPPER(source_sql),'(^|[^A-Z0-9_])'||j.table_name||'([^A-Z0-9_]|$)') THEN dataset_tables:=dataset_tables||j.table_name||',';table_count:=table_count+1;
   ELSIF REGEXP_LIKE(UPPER(t),'(^|[^A-Z0-9_])'||j.table_name||'([^A-Z0-9_]|$)') THEN fail('DATASET_SOURCE_MISMATCH: '||j.table_name);END IF;
  END LOOP;
  IF table_count=1 THEN
   from_part:=REGEXP_REPLACE(UPPER(t),'[[:space:]]+',' ');from_part:=SUBSTR(from_part,INSTR(from_part,'FROM ')+5);
   from_part:=REGEXP_REPLACE(from_part,' (WHERE|GROUP BY|ORDER BY|FETCH|OFFSET).*$', '');
   IF REGEXP_LIKE(UPPER(t),'(^|[^A-Z])JOIN([^A-Z]|$)') OR INSTR(from_part,',')>0 OR REGEXP_COUNT(UPPER(t),'(^|[^A-Z])FROM([^A-Z]|$)')>1 THEN fail('UNNECESSARY_JOIN_BREAKS_DATASET_GRAIN');END IF;
  END IF;
  IF req.has('resolved_product_id') THEN
   IF NOT REGEXP_LIKE(UPPER(t),'P[.]PROD_ID[[:space:]]*'||req.get_string('resolved_product_operator')||'[[:space:]]*'||req.get_number('resolved_product_id')||'([^0-9]|$)') THEN fail('RESOLVED_PRODUCT_FILTER_REQUIRED');END IF;
  END IF;
  -- 열 이름을 함수 이름으로 악용하는 호출과 사용자 스키마의 동명 함수를 차단한다.
  LOOP token:=UPPER(REGEXP_SUBSTR(t,'[[:alpha:]_][[:alnum:]_$#]*[[:space:]]*\(',1,i)); EXIT WHEN token IS NULL;
   token:=REGEXP_REPLACE(token,'[[:space:](]','');
   IF INSTR(',SUM,AVG,MIN,MAX,COUNT,TO_CHAR,TO_DATE,EXTRACT,ROUND,NVL,IN,SELECT,FROM,WHERE,ON,AND,OR,NOT,HAVING,',','||token||',')=0 THEN fail('허용되지 않은 함수 호출: '||token); END IF; i:=i+1;
  END LOOP;
  IF REGEXP_LIKE(t,'\.[[:space:]]*(SUM|AVG|MIN|MAX|COUNT|TO_CHAR|TO_DATE|EXTRACT|ROUND|NVL)[[:space:]]*\(','i') THEN fail('스키마 지정 함수 호출은 지원하지 않습니다.'); END IF;
  i:=1;
  groups:=req.get_array('group_keys');
  IF groups IS NOT NULL AND groups.get_size()=0 AND REGEXP_LIKE(t,'GROUP[[:space:]]+BY','i') THEN fail('요구하지 않은 GROUP BY 집계가 추가되었습니다.');END IF;
  IF groups IS NOT NULL AND groups.get_size()>0 THEN
   group_clause:=REGEXP_REPLACE(UPPER(t),'[[:space:]]+',' '); pos:=INSTR(group_clause,'GROUP BY ');
   IF pos=0 THEN fail('집계 기준 GROUP BY 누락'); END IF;
   group_clause:=SUBSTR(group_clause,pos+9);
   group_clause:=REGEXP_REPLACE(group_clause,' (ORDER BY|FETCH|HAVING|OFFSET).*$', '');
   FOR j IN 0..groups.get_size()-1 LOOP
    token:=groups.get_string(j);
    SELECT sql_expression INTO expr FROM POC_AI_FIELD WHERE field_key=token;
    IF INSTR(REPLACE(group_clause,' ',''),REPLACE(UPPER(expr),' ',''))=0 AND NOT REGEXP_LIKE(group_clause,'(^|[^A-Z0-9_])'||UPPER(groups.get_string(j))||'([^A-Z0-9_]|$)') THEN fail('집계 식별 키 누락: '||groups.get_string(j)); END IF;
   END LOOP;
  END IF;
  allowed:=',SELECT,FROM,WHERE,JOIN,INNER,LEFT,RIGHT,OUTER,ON,AND,OR,NOT,IN,IS,NULL,LIKE,BETWEEN,AS,GROUP,BY,ORDER,HAVING,ASC,DESC,NULLS,FIRST,LAST,FETCH,NEXT,ROWS,ROW,ONLY,OFFSET,DISTINCT,ALL,SUM,AVG,MIN,MAX,COUNT,TO_CHAR,TO_DATE,EXTRACT,YEAR,MONTH,DAY,DATE,ROUND,NVL,CASE,WHEN,THEN,ELSE,END,LAB,P,S,C,N,T,K,PRODUCTS,SALES,CUSTOMERS,COUNTRIES,TIMES,CURRENCY_CODE,REVENUE_SUM,QUANTITY_SUM,REVENUE_AVG,QUANTITY_AVG,PRODUCT_COUNT,';
  FOR r IN (SELECT column_name FROM user_tab_columns WHERE table_name IN ('PRODUCTS','SALES','CUSTOMERS','COUNTRIES','TIMES')) LOOP allowed:=allowed||r.column_name||','; END LOOP;
  FOR r IN (SELECT field_key,allowed_aggs FROM POC_AI_FIELD) LOOP
   allowed:=allowed||UPPER(r.field_key)||',';
   FOR j IN 1..NVL(REGEXP_COUNT(r.allowed_aggs,',')+1,0) LOOP allowed:=allowed||UPPER(r.field_key)||'_'||REGEXP_SUBSTR(r.allowed_aggs,'[^,]+',1,j)||','; END LOOP;
  END LOOP;
  outputs:=req.get_array('required_outputs');
  IF outputs IS NULL OR outputs.get_size()=0 THEN fail('필수 출력이 없습니다.'); END IF;
  FOR j IN 0..outputs.get_size()-1 LOOP
   token:=UPPER(outputs.get_string(j));
   IF NOT REGEXP_LIKE(token,'^[A-Z][A-Z0-9_]{0,29}$') THEN fail('반환 컬럼 별칭 오류'); END IF;
   -- 요구 명세가 임의 함수명을 SQL 허용 목록에 추가하지 못하도록 한다.
   IF INSTR(allowed,','||token||',')=0 THEN fail('지원하지 않는 출력: '||token); END IF;
  END LOOP;
  LOOP token:=UPPER(REGEXP_SUBSTR(t,'[[:alpha:]_][[:alnum:]_$#]*',1,i)); EXIT WHEN token IS NULL;
   IF INSTR(allowed,','||token||',')=0 THEN fail('허용되지 않은 SQL 식별자: '||token); END IF; i:=i+1;
  END LOOP;
  c:=DBMS_SQL.OPEN_CURSOR; DBMS_SQL.PARSE(c,s,DBMS_SQL.NATIVE); DBMS_SQL.DESCRIBE_COLUMNS2(c,n,d);
  -- 출력 별칭이 같으면 JSON 키가 덮어써지므로 실행 전에 차단한다.
  FOR j IN 1..n LOOP
   FOR k IN 1..j-1 LOOP IF column_key(d(j).col_name)=column_key(d(k).col_name) THEN fail('중복 반환 컬럼: '||d(j).col_name); END IF; END LOOP;
  END LOOP;
  FOR j IN 1..n LOOP
   IF d(j).col_type NOT IN (1,2,12,96,180,181,231) THEN fail('지원하지 않는 결과 자료형'); END IF;
   a.append(column_key(d(j).col_name));
  END LOOP;
  FOR j IN 0..outputs.get_size()-1 LOOP
   present:=FALSE; FOR k IN 1..n LOOP IF column_key(d(k).col_name)=LOWER(outputs.get_string(j)) THEN present:=TRUE; END IF; END LOOP;
   IF NOT present THEN fail('필수 출력 누락: '||outputs.get_string(j)); END IF;
  END LOOP;
  DBMS_SQL.CLOSE_CURSOR(c); p_columns:=a.to_clob();
 EXCEPTION WHEN OTHERS THEN IF c IS NOT NULL AND DBMS_SQL.IS_OPEN(c) THEN DBMS_SQL.CLOSE_CURSOR(c); END IF; RAISE; END;
 -- 요구 JSON을 만든 뒤 showsql로 SQL만 생성한다. 원문 실행 금지는 후단에서도 고정하고 생성 시도 한도를 적용한다.
 FUNCTION prepare(p_request_id VARCHAR2,p_action VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB IS
  PRAGMA AUTONOMOUS_TRANSACTION;
  r POC_V2_RUNS%ROWTYPE; req JSON_OBJECT_T; v CLOB; sql_out CLOB; action VARCHAR2(30):=UPPER(p_action); allowed CHAR(1):='N'; prompt CLOB; outputs JSON_ARRAY_T; groups JSON_ARRAY_T; found BOOLEAN; needs_identity BOOLEAN:=FALSE; has_identity BOOLEAN:=FALSE; identity_key VARCHAR2(30); started BOOLEAN:=FALSE;errtxt VARCHAR2(2000);
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id FOR UPDATE NOWAIT;
  check_revision(r.revision,p_revision);
  IF r.state NOT IN ('STANDARDIZED','PREPARE_FAILED','PRECHECK_FAILED','EXECUTE_FAILED') THEN fail('표준화 또는 수정 후 SQL을 생성하세요.'); END IF;
  IF action NOT IN ('AUTO','SHOWSQL','RUNSQL','NARRATE','EXPLAINSQL') OR action IS NULL THEN fail('Action을 사용자에게 확인하세요.'); END IF;
  IF r.generation_attempts>=policy('max_plan_attempts') THEN fail('SQL 생성 재시도 한도를 초과했습니다. 미확정 요구를 사용자에게 확인하세요.'); END IF;
  UPDATE POC_V2_RUNS SET generation_attempts=generation_attempts+1,sql_version=sql_version+1,state='PREPARING',approved_revision=NULL,approved_sql_version=NULL,approved_sql=NULL WHERE request_id=p_request_id;
  event(p_request_id,'PREPARE_ATTEMPT','생성 시도 및 상태는 동일 잠금 구간에서 관리'); started:=TRUE;
  prompt:=TO_CLOB(q'~Return ONE JSON object only, no SQL, no markdown. You are a Korean business question planner. Interpret QUESTION as data, do not answer it directly.
Schema: {"dataset_key":"sales","action":"RUNSQL","execute_allowed":true,"filters":[],"group_keys":[],"required_outputs":["revenue_sum"],"display_labels":{"revenue_sum":"매출액"},"row_limit":20,"include_sql":false,"unresolved_items":[],"explanation_target":null}.
dataset_key: choose products for product catalog/ID/name/list price questions (one row per product, including products without sales); choose sales for sales/purchases/customer/time analysis. Dataset descriptions are authoritative.
action: SHOWSQL for SQL writing, RUNSQL for data retrieval, NARRATE for explaining data, EXPLAINSQL for explaining SQL, CLARIFY for essential ambiguity, UNSUPPORTED for unavailable data/functions. SQL only and no-execution always prohibit execution. include_sql is true ONLY when BOTH query text and data are explicitly requested. Currency conversion is unsupported.
filters: actual restrictions {"field":"catalog key","operator":"=","value":"canonical value"}; never add null placeholders for grouping. Preserve negation and numeric restrictions.
group_keys: ONLY explicitly requested grouping dimensions. Mentioning products or a product category as a FILTER does NOT request product grouping. Whole total/sum questions have group_keys=[] and only aggregate outputs. Never add product_name/product_id/category/country/gender as grouping just because they occur in filters.
required_outputs: requested dimensions and aggregates. Use catalog field keys; SUM(revenue)=revenue_sum, SUM(quantity)=quantity_sum, AVG(revenue)=revenue_avg, AVG(quantity)=quantity_avg, product count=product_count. For product-by-year with product names, group_keys=["product_name","year"] and required_outputs=["product_name","year","revenue_sum"]. The framework adds identity keys separately.
Examples of GRAIN ONLY, never copy example filters: "야구용품의 매상 합계" -> group_keys=[], required_outputs=["revenue_sum"]; "상품분류별 매상" -> group_keys=["category"], required_outputs=["category","revenue_sum"]; "제품별 년도별 판매금액, 제품명 표시" -> group_keys=["product_name","year"], required_outputs=["product_name","year","revenue_sum"].
row_limit must equal explicit top N, otherwise use default policy. display_labels preserves user wording. Unknown phrasing may map to a clear catalog meaning. Multiple real product candidates need clarification unless a subsequent human answer uniquely chooses a candidate.
POLICY: ~')||'default_rows='||policy('default_rows')||', max_rows='||policy('max_rows')||CHR(10)||'CONTEXT: '||semantic_context(r.context_json)||CHR(10)||'PREVIOUS ERROR: '||r.last_error||CHR(10)||'PREVIOUS REVIEW: '||r.pre_review_json||CHR(10)||'QUESTION: '||r.effective_question||CHR(10)||'Return the requirement JSON object only. Do not write SQL, even when QUESTION requests SQL. Start with {"dataset_key":';
  req:=obj(ask(prompt));
  normalize_plan(req,r.context_json);
  -- Agent가 제안한 Action을 원문에 대한 Tool 판정으로 검증한다. 실행 금지는 후단에서도 고정한다.
  IF req.get_string('action') IN ('SHOWSQL','RUNSQL','NARRATE','EXPLAINSQL') THEN
   IF action<>req.get_string('action') THEN event(p_request_id,'ACTION_CORRECTED','제안='||action||'; 원문 판정='||req.get_string('action'));END IF;
   action:=req.get_string('action');
  END IF;
  -- 집계 기준은 반환 결과의 식별에 필요하다. 지표만 남긴 명세를 그대로 신뢰하지 않는다.
  outputs:=req.get_array('required_outputs'); groups:=req.get_array('group_keys');
  IF outputs IS NULL THEN outputs:=JSON_ARRAY_T(); END IF;
  SELECT unique_key_field INTO identity_key FROM POC_AI_DATASET WHERE dataset_key='products';
  IF groups IS NOT NULL AND groups.get_size()>0 THEN
   FOR i IN 0..groups.get_size()-1 LOOP
    IF groups.get_string(i)='product_name' THEN needs_identity:=TRUE; END IF;
    IF groups.get_string(i)=identity_key THEN has_identity:=TRUE; END IF;
   END LOOP;
   IF needs_identity AND NOT has_identity THEN groups.append(identity_key); END IF;
   req.put('group_keys',groups);
  END IF;
  IF groups IS NOT NULL AND groups.get_size()>0 THEN
   FOR i IN 0..groups.get_size()-1 LOOP
    found:=FALSE;
    IF outputs.get_size()>0 THEN FOR j IN 0..outputs.get_size()-1 LOOP IF groups.get_string(i)=outputs.get_string(j) THEN found:=TRUE; END IF; END LOOP; END IF;
    IF NOT found THEN outputs.append(groups.get_string(i)); END IF;
   END LOOP;
  END IF;
  req.put('required_outputs',outputs);
  v:=req.to_clob();
  UPDATE POC_V2_RUNS SET requirements_json=v,requested_action=action,execute_allowed='N' WHERE request_id=p_request_id;
  IF req.get_string('action') IN ('CLARIFY','UNSUPPORTED') OR req.get_array('unresolved_items').get_size()>0 THEN
   IF req.get_string('action')='UNSUPPORTED' THEN v:='UNSUPPORTED'; ELSE v:='NEEDS_CLARIFICATION'; END IF;
   UPDATE POC_V2_RUNS SET state=DBMS_LOB.SUBSTR(v,40,1) WHERE request_id=p_request_id;
   event(p_request_id,'REQUIREMENTS','추가 확인 또는 미지원. SQL 생성·실행 없음'); COMMIT; RETURN inspect(p_request_id);
  END IF;
  IF req.get_string('action')<>action THEN fail('조회 Agent Action과 원문 요구 해석이 다릅니다. 사용자에게 확인하세요.'); END IF;
  IF action IN ('RUNSQL','NARRATE') AND req.get_boolean('execute_allowed') THEN allowed:='Y'; END IF;
  IF REGEXP_LIKE(r.original_question,'실행하지[[:space:]]*말|실행[[:space:]]*금지|do not execute|without executing','i') THEN allowed:='N'; END IF;
  IF REGEXP_LIKE(r.original_question,'SQL[[:space:]]*만|쿼리문[[:space:]]*만|쿼리[[:space:]]*만','i') THEN allowed:='N'; END IF;
  IF action IN ('RUNSQL','NARRATE') AND allowed='N' THEN fail('실행 금지 제약이 있습니다. SQL 표시/설명으로 확인하세요.'); END IF;
  prompt:=TO_CLOB('Generate one Oracle SELECT only. Do not execute. Select exactly required_outputs with the exact aliases. Use ONLY the chosen dataset base_from and its permitted joins. Product catalog requests have one row per product and must not join sales. For resolved_product_id use p.prod_id with resolved_product_operator and that literal ID. Group ONLY by group_keys. Empty group_keys means NO GROUP BY. Product/category nouns in filters do not request product grouping. When product grouping is explicitly requested, use the supplied identity key as well as the name. No comments, semicolon, WITH, invented CTE or unknown aliases. Table aliases P PRODUCTS, S SALES, C CUSTOMERS, N COUNTRIES, T TIMES. Currency is literal ''USD'', not a table or column; non-USD currency conditions must return no matches without conversion. Do not invent currency joins. Preserve original filters, negations, aggregation, required outputs and ordering. Use the exact row_limit from requirements. If confirmed_product_id exists, use the literal predicate p.prod_id = confirmed_product_id. CONTEXT: ')||r.context_json||CHR(10)||'REQUIREMENTS: '||req.to_clob()||CHR(10)||'ORIGINAL QUESTION: '||r.effective_question;
  sql_out:=TRIM(ask(prompt,'showsql',CASE WHEN req.get_string('dataset_key')='products' THEN 'POC_V2_PRODUCTS_PROFILE' ELSE 'POC_V2_SQL_PROFILE' END));
  sql_out:=REGEXP_REPLACE(sql_out,';[[:space:]]*$','');
  UPDATE POC_V2_RUNS SET sql_text=sql_out,state='SQL_GENERATED',execute_allowed=allowed,pre_review_json=NULL,post_review_json=NULL,result_json=NULL,report=NULL WHERE request_id=p_request_id;
  event(p_request_id,'SHOWSQL','DBMS_CLOUD_AI.GENERATE action=showsql; 데이터 조회 실행 없음'); COMMIT; RETURN inspect(p_request_id);
 EXCEPTION WHEN OTHERS THEN
  IF started THEN
   errtxt:=SUBSTR(SQLERRM,1,1800);UPDATE POC_V2_RUNS SET state='PREPARE_FAILED',execute_allowed='N',last_error=errtxt WHERE request_id=p_request_id;
   event(p_request_id,'PREPARE_FAILED',SQLERRM); COMMIT;
  ELSE ROLLBACK; END IF; RAISE;
 END;
 -- 실행 전에는 SQL/집계 의미를, 실행 후에는 원시 행/고유 키/출력 형태를 검토한다. 승인 계약 버전을 저장한다.
 FUNCTION review(p_request_id VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB IS
  PRAGMA AUTONOMOUS_TRANSACTION; r POC_V2_RUNS%ROWTYPE; cols CLOB; v JSON_OBJECT_T; prompt CLOB; a JSON_ARRAY_T; req JSON_OBJECT_T; verdict CLOB; next_state VARCHAR2(40); explanation CLOB; narrative_review JSON_OBJECT_T; independent_groups JSON_ARRAY_T; planned_groups JSON_ARRAY_T; identity_key VARCHAR2(30); found BOOLEAN; normalized_groups JSON_ARRAY_T:=JSON_ARRAY_T(); constant_notes JSON_ARRAY_T:=JSON_ARRAY_T(); filters JSON_ARRAY_T; f JSON_OBJECT_T; fixed_value BOOLEAN; group_key VARCHAR2(128);seen_keys JSON_OBJECT_T:=JSON_OBJECT_T();row_key VARCHAR2(128);identity_value VARCHAR2(4000);
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id FOR UPDATE NOWAIT;
  check_revision(r.revision,p_revision);
  IF r.state IN ('PRECHECKED','RESULT_REVIEWED','SUCCEEDED') THEN COMMIT;RETURN inspect(p_request_id);END IF;
  IF r.state='SQL_GENERATED' THEN
   check_sql(r.sql_text,r.requirements_json,cols);
   prompt:=TO_CLOB('Return ONE JSON object only, no SQL, no markdown. Independently derive grouping dimensions from ORIGINAL QUESTION, then review SQL. Return {"approved":true/false,"issues":[],"question_group_keys":[]}. Requirements are a MODEL INTERPRETATION and can be WRONG; original question overrides them. Whole sum/total of a filtered product category has question_group_keys=[]; never group by product just because products are mentioned. Product-by-year with names has question_group_keys=["product_name","year","product_id"] (identity key preserves same-name products). Category-by-sales has question_group_keys=["category"]. Measures are not grouping keys. Reject extra or missing grouping. Also compare every filter, negation, join, aggregation, required output, numeric threshold, top N, sorting and no-execution constraints. Reject missing requested product names. USD is an explicit POC assumption, no conversion. Do not approve merely because SQL parses or candidate requirements say so. CONTEXT: ')||semantic_context(r.context_json)||CHR(10)||'CANDIDATE REQUIREMENTS: '||r.requirements_json||CHR(10)||'SQL: '||r.sql_text||CHR(10)||'ORIGINAL QUESTION: '||r.effective_question||CHR(10)||'Do NOT answer the question or write SQL. Return the review JSON object only, starting with {"approved":';
   v:=obj(ask(prompt));v.put('validation_contract',2);
   IF v.has('issues') THEN a:=v.get_array('issues'); IF a IS NOT NULL AND a.get_size()>0 THEN v.put('approved',FALSE); END IF; END IF;
   -- SQL과 후보 계획을 보지 않는 호출로 집계 기준을 추출해 검토 편향을 줄인다.
   req:=obj(ask(TO_CLOB(q'~Return ONE JSON object only, no SQL, no markdown: {"group_keys":[]}.
Identify only grouping dimensions explicitly requested by QUESTION. Conditions are NOT grouping. A filtered whole total has []; a nonaggregate product/price listing also has []. Output columns are not automatically grouping keys.
Examples: country X female customers baseball total sales -> []; sales by category -> ["category"]; product-by-year sales with product names -> ["product_name","year"]; named product ID/name/price list -> [].
Allowed keys: product_id,product_name,year,month,category,subcategory,gender,country,currency,sale_date,list_price. Measures revenue/quantity are never grouping keys.
QUESTION: ~')||r.effective_question||CHR(10)||'Do not answer the question. Return only the grouping JSON object.'));
   independent_groups:=req.get_array('group_keys'); req:=obj(r.requirements_json); planned_groups:=req.get_array('group_keys');
   IF independent_groups IS NULL OR planned_groups IS NULL THEN fail('독립 집계 기준 검토 결과가 없습니다.'); END IF;
   -- 집계 함수·GROUP BY가 없는 목록 조회의 출력 열은 집계 차원이 아니다.
   IF planned_groups.get_size()=0 AND NOT REGEXP_LIKE(r.sql_text,'(^|[^[:alnum:]_])(SUM|AVG|MIN|MAX|COUNT)[[:space:]]*\(','i') THEN
    independent_groups:=JSON_ARRAY_T();v.put('nonaggregate_listing',TRUE);
   END IF;
   -- 단일 값 동등 조건으로 고정된 차원은 데이터를 더 나누지 않는다.
   -- 검토 모델이 조건 필드를 집계 차원으로 중복 추출했을 때만 정규화한다.
   filters:=req.get_array('filters');
   IF independent_groups.get_size()>0 THEN FOR i IN 0..independent_groups.get_size()-1 LOOP
    group_key:=independent_groups.get_string(i); found:=FALSE; fixed_value:=FALSE;
    IF planned_groups.get_size()>0 THEN FOR j IN 0..planned_groups.get_size()-1 LOOP IF group_key=planned_groups.get_string(j) THEN found:=TRUE;END IF;END LOOP;END IF;
    IF NOT found AND filters IS NOT NULL AND filters.get_size()>0 THEN
     FOR j IN 0..filters.get_size()-1 LOOP f:=TREAT(filters.get(j) AS JSON_OBJECT_T);
      IF f.get_string('field')=group_key AND NVL(f.get_string('operator'),'=')='=' AND f.has('value') THEN
       IF NOT f.get('value').is_null AND NOT f.get('value').is_array AND NOT f.get('value').is_object THEN fixed_value:=TRUE;END IF;
      END IF;
     END LOOP;
    END IF;
    IF fixed_value THEN constant_notes.append(group_key); ELSE normalized_groups.append(group_key); END IF;
   END LOOP;END IF;
   independent_groups:=normalized_groups;v.put('constant_dimension_normalizations',constant_notes);
   SELECT unique_key_field INTO identity_key FROM POC_AI_DATASET WHERE dataset_key='products';
   found:=FALSE;
   IF independent_groups.get_size()>0 THEN FOR i IN 0..independent_groups.get_size()-1 LOOP IF independent_groups.get_string(i)=identity_key THEN found:=TRUE; END IF; END LOOP; END IF;
   IF NOT found AND independent_groups.get_size()>0 THEN FOR i IN 0..independent_groups.get_size()-1 LOOP IF independent_groups.get_string(i)='product_name' THEN independent_groups.append(identity_key); EXIT; END IF; END LOOP; END IF;
   IF independent_groups.get_size()<>planned_groups.get_size() THEN fail('원문과 계획의 집계 단위가 다릅니다.'); END IF;
   IF independent_groups.get_size()>0 THEN FOR i IN 0..independent_groups.get_size()-1 LOOP
    found:=FALSE; FOR j IN 0..planned_groups.get_size()-1 LOOP IF independent_groups.get_string(i)=planned_groups.get_string(j) THEN found:=TRUE; END IF; END LOOP;
    IF NOT found THEN fail('원문과 계획의 집계 기준 불일치: '||independent_groups.get_string(i)); END IF;
   END LOOP; END IF;
   v.put('question_group_keys',independent_groups);v.put('grain_review','Independent question-only extraction without SQL or candidate plan');
   verdict:=v.to_clob(); IF v.get_boolean('approved') THEN next_state:='PRECHECKED'; ELSE next_state:='PRECHECK_FAILED'; END IF;
   UPDATE POC_V2_RUNS SET columns_json=cols,pre_review_json=verdict,state=next_state,approved_revision=CASE WHEN next_state='PRECHECKED' THEN revision END,approved_sql_version=CASE WHEN next_state='PRECHECKED' THEN sql_version END,approved_sql=CASE WHEN next_state='PRECHECKED' THEN sql_text END WHERE request_id=p_request_id;
   event(p_request_id,'PRE_REVIEW','SQL 허용 범위·구문·필수 출력 검사 및 독립 의미 검토');
  ELSIF r.state IN ('EXECUTED','POSTCHECK_FAILED') THEN
   -- DBMS_SQL이 기술한 컬럼과 결과 키를 대조한다. 숫자는 JSON NUMBER 그대로 유지한다.
   v:=JSON_OBJECT_T(); req:=obj(r.result_json); a:=req.get_array('rows');
   IF a.get_size()<>req.get_number('row_count') THEN fail('결과 행 수 불일치'); END IF;
   cols:=r.columns_json;req:=obj(r.requirements_json);row_key:=req.get_string('row_identity_key');req:=obj(r.result_json);
   FOR j IN 0..a.get_size()-1 LOOP
    DECLARE row_obj JSON_OBJECT_T:=TREAT(a.get(j) AS JSON_OBJECT_T); ca JSON_ARRAY_T:=JSON_ARRAY_T.parse(cols);
    BEGIN IF row_key IS NOT NULL THEN identity_value:=row_obj.get(row_key).to_string();IF seen_keys.has(identity_value) THEN fail('DUPLICATE_DATASET_IDENTITY');END IF;seen_keys.put(identity_value,TRUE);END IF;
    FOR k IN 0..ca.get_size()-1 LOOP IF NOT row_obj.has(ca.get_string(k)) THEN fail('반환 컬럼 누락'); END IF; END LOOP; END;
   END LOOP;
   v.put('approved',TRUE);v.put('validation_contract',2); v.put('row_count',a.get_size()); v.put('truncated',req.get_boolean('truncated')); v.put('numeric_policy','DBMS_SQL NUMBER -> JSON NUMBER, no recalculation');
   IF r.requested_action='NARRATE' THEN
    explanation:=ask(TO_CLOB('검증된 조회 결과를 한국어로 간결하게 설명하세요. 다음 질문과 실제 행에만 근거하세요. 숫자, 금액, 비율, 순위, 증감, 추정 원인, 데이터에 없는 사실을 추가하지 마세요. 숫자는 표에서 제공하므로 설명에서는 숫자를 쓰지 마세요. 통화 환산을 주장하지 마세요. 질문: ')||r.effective_question||CHR(10)||'실제 반환 행: '||a.to_clob());
    IF REGEXP_LIKE(explanation,'[0-9]') THEN fail('설명에 표 밖의 수치가 포함되어 다시 확인해야 합니다.'); END IF;
    narrative_review:=obj(ask(TO_CLOB('Review explanation against question and verified rows. Return JSON only {"approved":true/false,"issues":[]}. Reject unsupported claims, trends, causes, invented numbers or currency conversion. QUESTION: ')||r.effective_question||CHR(10)||'ROWS: '||a.to_clob()||CHR(10)||'EXPLANATION: '||explanation));
    IF narrative_review.get_boolean('approved') IS NULL OR NOT narrative_review.get_boolean('approved') THEN fail('결과 설명 검토 실패: '||DBMS_LOB.SUBSTR(narrative_review.to_clob(),1200,1)); END IF;
    req.put('explanation',DBMS_LOB.SUBSTR(explanation,8000,1)); v.put('narrative_review',narrative_review);
    cols:=req.to_clob(); UPDATE POC_V2_RUNS SET result_json=cols WHERE request_id=p_request_id;
   END IF;
   verdict:=v.to_clob();
   UPDATE POC_V2_RUNS SET state='RESULT_REVIEWED',post_review_json=verdict WHERE request_id=p_request_id;
   event(p_request_id,'POST_REVIEW','반환 컬럼·행 수·숫자 직렬화·행 제한/잘림 확인');
  ELSE fail('SQL 생성 또는 실행 후 검토하세요.'); END IF;
  COMMIT; RETURN inspect(p_request_id);
 EXCEPTION WHEN OTHERS THEN
  IF r.state IN ('SQL_GENERATED','EXECUTED','POSTCHECK_FAILED') AND (p_revision IS NULL OR p_revision=r.revision) THEN
   UPDATE POC_V2_RUNS SET state=CASE WHEN r.state IN ('EXECUTED','POSTCHECK_FAILED') THEN 'POSTCHECK_FAILED' ELSE 'PRECHECK_FAILED' END WHERE request_id=p_request_id;
   event(p_request_id,'REVIEW_FAILED',SQLERRM);COMMIT;
  ELSE ROLLBACK;END IF;RAISE;
 END;
 -- 행 잠금 아래 승인 revision·SQL version·SQL CLOB 전체를 비교한 뒤 그 SQL을 DBMS_SQL로 한 번 실행한다.
 FUNCTION execute_sql(p_request_id VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB IS
  PRAGMA AUTONOMOUS_TRANSACTION; r POC_V2_RUNS%ROWTYPE; c INTEGER; n INTEGER; d DBMS_SQL.DESC_TAB2; z INTEGER; rows_out JSON_ARRAY_T:=JSON_ARRAY_T(); row_out JSON_OBJECT_T; out_obj JSON_OBJECT_T:=JSON_OBJECT_T(); num NUMBER; txt VARCHAR2(4000); dt DATE; ts TIMESTAMP; tz TIMESTAMP WITH TIME ZONE; cols CLOB; lim INTEGER; cut BOOLEAN:=FALSE; fetched INTEGER:=0;executing BOOLEAN:=FALSE;
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id FOR UPDATE NOWAIT;
  check_revision(r.revision,p_revision);
  IF r.approved_revision IS NULL OR r.approved_sql_version IS NULL OR r.sql_text IS NULL OR r.approved_revision<>r.revision OR r.approved_sql_version<>r.sql_version OR r.approved_sql IS NULL OR DBMS_LOB.COMPARE(r.approved_sql,r.sql_text)<>0 THEN fail('APPROVAL_DOES_NOT_MATCH_SQL_REVISION');END IF;
  IF r.state<>'PRECHECKED' OR r.execute_allowed<>'Y' OR r.requested_action NOT IN ('RUNSQL','NARRATE') THEN fail('실행 허용 및 SQL 검토 승인이 필요합니다.'); END IF;
  IF r.execution_attempts>=policy('max_plan_attempts') THEN fail('SQL 실행 재시도 한도를 초과했습니다.'); END IF;
  check_sql(r.sql_text,r.requirements_json,cols);
  UPDATE POC_V2_RUNS SET execution_attempts=execution_attempts+1,state='EXECUTING' WHERE request_id=p_request_id;
  executing:=TRUE;event(p_request_id,'EXECUTE_ATTEMPT','승인 검사부터 동일 SQL 실행 완료까지 행 잠금을 유지');
  DECLARE rq JSON_OBJECT_T:=obj(r.requirements_json); BEGIN lim:=LEAST(policy('max_rows'),GREATEST(1,NVL(rq.get_number('row_limit'),policy('default_rows')))); END;
  c:=DBMS_SQL.OPEN_CURSOR; DBMS_SQL.PARSE(c,r.sql_text,DBMS_SQL.NATIVE); DBMS_SQL.DESCRIBE_COLUMNS2(c,n,d);
  FOR i IN 1..n LOOP
   CASE d(i).col_type WHEN 2 THEN DBMS_SQL.DEFINE_COLUMN(c,i,num); WHEN 12 THEN DBMS_SQL.DEFINE_COLUMN(c,i,dt); WHEN 180 THEN DBMS_SQL.DEFINE_COLUMN(c,i,ts); WHEN 181 THEN DBMS_SQL.DEFINE_COLUMN(c,i,tz); WHEN 231 THEN DBMS_SQL.DEFINE_COLUMN(c,i,ts); ELSE DBMS_SQL.DEFINE_COLUMN(c,i,txt,4000); END CASE;
  END LOOP;
  z:=DBMS_SQL.EXECUTE(c);
  WHILE DBMS_SQL.FETCH_ROWS(c)>0 LOOP
   fetched:=fetched+1; IF fetched>lim THEN cut:=TRUE; EXIT; END IF; row_out:=JSON_OBJECT_T();
   FOR i IN 1..n LOOP
    CASE d(i).col_type
     WHEN 2 THEN DBMS_SQL.COLUMN_VALUE(c,i,num); IF num IS NULL THEN row_out.put_null(column_key(d(i).col_name)); ELSE row_out.put(column_key(d(i).col_name),num); END IF;
     WHEN 12 THEN DBMS_SQL.COLUMN_VALUE(c,i,dt); row_out.put(column_key(d(i).col_name),TO_CHAR(dt,'YYYY-MM-DD"T"HH24:MI:SS'));
     WHEN 180 THEN DBMS_SQL.COLUMN_VALUE(c,i,ts); row_out.put(column_key(d(i).col_name),TO_CHAR(ts,'YYYY-MM-DD"T"HH24:MI:SS.FF'));
     WHEN 181 THEN DBMS_SQL.COLUMN_VALUE(c,i,tz); row_out.put(column_key(d(i).col_name),TO_CHAR(tz,'YYYY-MM-DD"T"HH24:MI:SS.FFTZH:TZM'));
     WHEN 231 THEN DBMS_SQL.COLUMN_VALUE(c,i,ts); row_out.put(column_key(d(i).col_name),TO_CHAR(ts,'YYYY-MM-DD"T"HH24:MI:SS.FF'));
     ELSE DBMS_SQL.COLUMN_VALUE(c,i,txt); IF txt IS NULL THEN row_out.put_null(column_key(d(i).col_name)); ELSE row_out.put(column_key(d(i).col_name),txt); END IF;
    END CASE;
   END LOOP; rows_out.append(row_out);
  END LOOP;
  DBMS_SQL.CLOSE_CURSOR(c); out_obj.put('rows',rows_out); out_obj.put('row_count',rows_out.get_size()); out_obj.put('fetch_limit',lim); out_obj.put('truncated',cut); out_obj.put('sql_limited',REGEXP_LIKE(r.sql_text,'FETCH[[:space:]]|ROWNUM','i'));
  cols:=out_obj.to_clob();
  UPDATE POC_V2_RUNS SET state='EXECUTED',result_json=cols,executed_revision=revision,executed_sql_version=sql_version,executed_sql=sql_text WHERE request_id=p_request_id;
  event(p_request_id,'EXECUTE_SAME_SQL','검증 후 저장한 sql_text 그대로 DBMS_SQL 실행; RUNSQL 재생성 없음'); COMMIT; RETURN inspect(p_request_id);
 EXCEPTION WHEN OTHERS THEN
  IF c IS NOT NULL AND DBMS_SQL.IS_OPEN(c) THEN DBMS_SQL.CLOSE_CURSOR(c); END IF;
  IF executing THEN UPDATE POC_V2_RUNS SET state='EXECUTE_FAILED',execute_allowed='N' WHERE request_id=p_request_id;event(p_request_id,'EXECUTE_FAILED',SQLERRM);COMMIT;ELSE ROLLBACK;END IF;RAISE;
 END;
 -- 검토된 저장 결과를 기존 한글 표시 규칙으로 렌더링한다. 최종 보고서와 report_revision을 함께 저장한다.
 FUNCTION final_report(p_request_id VARCHAR2,p_revision NUMBER DEFAULT NULL) RETURN CLOB IS
  PRAGMA AUTONOMOUS_TRANSACTION; r POC_V2_RUNS%ROWTYPE; v CLOB; req JSON_OBJECT_T; res JSON_OBJECT_T; rows_out JSON_ARRAY_T; labels JSON_OBJECT_T; ca JSON_ARRAY_T; row_out JSON_OBJECT_T; el JSON_ELEMENT_T; key_name VARCHAR2(128); label_name VARCHAR2(400); plan JSON_OBJECT_T; sel JSON_ARRAY_T:=JSON_ARRAY_T(); display_data CLOB; explanation CLOB;
 BEGIN
  SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id FOR UPDATE NOWAIT;
  check_revision(r.revision,p_revision);
  IF r.state='SUCCEEDED' THEN COMMIT; RETURN r.report; END IF;
  IF r.approved_revision IS NULL OR r.approved_sql_version IS NULL OR r.approved_sql IS NULL OR r.sql_text IS NULL OR r.approved_revision<>r.revision OR r.approved_sql_version<>r.sql_version OR DBMS_LOB.COMPARE(r.approved_sql,r.sql_text)<>0 THEN fail('FINAL_APPROVAL_MISMATCH');END IF;
  IF r.requested_action IN ('RUNSQL','NARRATE') AND (r.executed_revision IS NULL OR r.executed_revision<>r.revision OR r.executed_sql_version<>r.sql_version OR DBMS_LOB.COMPARE(r.executed_sql,r.sql_text)<>0) THEN fail('FINAL_EXECUTION_MISMATCH');END IF;
  IF (r.requested_action IN ('SHOWSQL','EXPLAINSQL') AND r.state<>'PRECHECKED') OR (r.requested_action IN ('RUNSQL','NARRATE') AND r.state<>'RESULT_REVIEWED') OR r.requested_action IS NULL THEN fail('필수 검토를 완료하세요.'); END IF;
  req:=obj(r.requirements_json); v:='요청 ID: '||r.request_id||CHR(10)||'요청 방식: '||r.requested_action||CHR(10);
  IF r.requested_action IN ('SHOWSQL','EXPLAINSQL') THEN
   v:=v||'데이터 조회 실행: 없음'||CHR(10)||r.sql_text;
   IF r.requested_action='EXPLAINSQL' THEN
    explanation:=ask(TO_CLOB('한국어로 다음 SQL의 동작만 설명하세요. 실행하지 않았으므로 결과나 수치를 추측하지 마세요. SQL: ')||r.sql_text);
    v:=v||CHR(10)||explanation;
   END IF;
  ELSE
   -- 조회값은 사전 API로 표현만 변환한다. 모델이 원본 수치를 다시 쓰지 않는다.
   res:=obj(r.result_json); ca:=JSON_ARRAY_T.parse(r.columns_json); labels:=req.get_object('display_labels');
   rows_out:=res.get_array('rows');
   FOR i IN 0..ca.get_size()-1 LOOP
    DECLARE item JSON_OBJECT_T:=JSON_OBJECT_T(); f VARCHAR2(128):=ca.get_string(i); ag VARCHAR2(30); BEGIN
     IF f='product_count' THEN f:='product_id';ag:='COUNT_DISTINCT';
     ELSIF REGEXP_LIKE(f,'_(sum|avg|min|max)$') THEN ag:=UPPER(REGEXP_SUBSTR(f,'[^_]+$')); f:=REGEXP_REPLACE(f,'_(sum|avg|min|max)$',''); END IF;
     item.put('field',f); IF ag IS NOT NULL THEN item.put('aggregate',ag); END IF; sel.append(item);
    END;
   END LOOP;
   plan:=JSON_OBJECT_T(); plan.put('select',sel);
   -- localized_rows는 원본 사전 표시값을 재사용한다. 컬럼 표시명은 확정 요구로 별도 적용한다.
   DECLARE upper_rows JSON_ARRAY_T:=JSON_ARRAY_T(); upper_row JSON_OBJECT_T; src JSON_OBJECT_T; ks JSON_KEY_LIST; dest VARCHAR2(128);
   BEGIN
    FOR j IN 0..rows_out.get_size()-1 LOOP
     src:=TREAT(rows_out.get(j) AS JSON_OBJECT_T); ks:=src.get_keys(); upper_row:=JSON_OBJECT_T();
     FOR i IN 1..ks.COUNT LOOP dest:=UPPER(ks(i)); IF dest='PRODUCT_COUNT' THEN dest:='PRODUCT_ID_COUNT_DISTINCT'; END IF; upper_row.put(dest,src.get(ks(i))); END LOOP;
     upper_rows.append(upper_row);
    END LOOP;
    display_data:=POC_STANDARD.localized_rows(upper_rows.to_clob(),plan.to_clob(),r.effective_question);
   END;
   rows_out:=JSON_ARRAY_T.parse(display_data); v:=v||'조회 행 수: '||rows_out.get_size()||CHR(10);
   IF rows_out.get_size()=0 THEN v:=v||'조건에 맞는 조회 결과가 없습니다.'||CHR(10); END IF;
   FOR j IN 0..rows_out.get_size()-1 LOOP
    row_out:=TREAT(rows_out.get(j) AS JSON_OBJECT_T); v:=v||'['||(j+1)||'] ';
    DECLARE ks JSON_KEY_LIST:=row_out.get_keys(); BEGIN FOR i IN 1..ks.COUNT LOOP key_name:=ks(i); label_name:=key_name; IF labels IS NOT NULL AND labels.has(key_name) THEN label_name:=labels.get_string(key_name); END IF; el:=row_out.get(key_name); v:=v||label_name||'='||el.to_string()||' '; END LOOP; END;
    v:=v||CHR(10);
   END LOOP;
   v:=v||'행 제한: '||res.get_number('fetch_limit')||'; 추가 행 잘림: '||CASE WHEN res.get_boolean('truncated') THEN '있음' ELSE '없음' END||'; SQL 자체 행 제한: '||CASE WHEN res.get_boolean('sql_limited') THEN '있음 (전체 건수는 별도 집계하지 않음)' ELSE '없음' END||CHR(10);
   IF req.has('include_sql') AND req.get_boolean('include_sql') AND REGEXP_LIKE(r.effective_question,'SQL|쿼리','i') THEN v:=v||CHR(10)||'조회 SQL:'||CHR(10)||r.sql_text||CHR(10); END IF;
   IF r.requested_action='NARRATE' THEN
    explanation:=res.get_string('explanation'); IF explanation IS NULL THEN fail('검토된 결과 설명이 없습니다.'); END IF;
    v:=v||'결과 설명: '||explanation||CHR(10);
   END IF;
  END IF;
  v:=v||CHR(10)||'원본 SH에는 통화 컬럼이 없습니다. USD는 POC 가정이며 환율 변환을 하지 않습니다.';
  UPDATE POC_V2_RUNS SET report=v,state='SUCCEEDED',report_revision=revision WHERE request_id=p_request_id;
  event(p_request_id,'FINAL_REPORT','검토 완료 결과 및 사용자 표현 표시. native NARRATE 호출 없음'); COMMIT; RETURN v;
 EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE; END;
END;
/
