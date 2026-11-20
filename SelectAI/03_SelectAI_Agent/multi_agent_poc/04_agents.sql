-- Oracle Native Agent 객체 등록. Tool 3개, Worker 3개, 일반 Task 3개와 Human Task 2개, Supervisor 1개, Team 1개.
-- 동일 Worker의 Task를 두 개 등록해도 Worker 수가 증가하는 것은 아니다. 설치 마지막에 Team을 비활성화한다.

-- 배치된 공개 GET_DEFINITION으로 생성. 설치 후 Team은 비활성화한다.
-- POC_V2_STANDARD_TOOL: PL/SQL 함수를 호출하는 도구. 입력은 저장된 request_id 하나.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'POC_V2_STANDARD_TOOL',
    attributes => '{"function":"POC_V2_STANDARD_FN","instruction":"Advance or inspect the saved request. Returns a JSON control record containing request_id, revision, state, next_agent, next_task, status, needs_human. Internal errors are not empty business results.","tool_inputs":[{"name":"P_REQUEST_ID","description":"Exact 32-character request_id from delegation. Never CURRENT, never a conversation ID."}]}',
    status => 'enabled'
  );
END;
/
-- POC_V2_STANDARD: 할당된 Task와 Tool로 한 단계를 처리하는 Worker.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'POC_V2_STANDARD',
    attributes => '{"profile_name":"POC_V2_AGENT_PROFILE","role":"Resolve saved business terms and handle real product clarification. Follow the assigned task and use only its available tools.","enable_human_tool":true}',
    status => 'enabled'
  );
END;
/
-- POC_V2_STANDARD_TASK: 대응 Tool 호출 후 Final Answer: DONE으로 끝내는 Task.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name => 'POC_V2_STANDARD_TASK',
    attributes => '{"instruction":"The delegated input {query} is the original 32-character request ID. Call POC_V2_STANDARD_TOOL once with that ID. After any real tool Observation, this delegated task is complete: output exactly Final Answer: DONE and stop. Never output bare JSON or repeat a tool call. Workflow continuation and any human questions are separate tasks controlled by the application.","tools":["POC_V2_STANDARD_TOOL"],"enable_human_tool":false}',
    status => 'enabled'
  );
END;
/
-- POC_V2_QUERY_TOOL: PL/SQL 함수를 호출하는 도구. 입력은 저장된 request_id 하나.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'POC_V2_QUERY_TOOL',
    attributes => '{"function":"POC_V2_QUERY_FN","instruction":"Advance or inspect the saved request. Returns a JSON control record containing request_id, revision, state, next_agent, next_task, status, needs_human. Internal errors are not empty business results.","tool_inputs":[{"name":"P_REQUEST_ID","description":"Exact 32-character request_id from delegation. Never CURRENT, never a conversation ID."}]}',
    status => 'enabled'
  );
END;
/
-- POC_V2_QUERY: 할당된 Task와 Tool로 한 단계를 처리하는 Worker.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'POC_V2_QUERY',
    attributes => '{"profile_name":"POC_V2_AGENT_PROFILE","role":"Handle saved query operations and real query-intent clarification. Follow the assigned task and use only its tools.","enable_human_tool":true}',
    status => 'enabled'
  );
END;
/
-- POC_V2_QUERY_TASK: 대응 Tool 호출 후 Final Answer: DONE으로 끝내는 Task.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name => 'POC_V2_QUERY_TASK',
    attributes => '{"instruction":"The delegated input {query} is the original 32-character request ID. Call POC_V2_QUERY_TOOL once with that ID. After any real tool Observation, this delegated task is complete: output exactly Final Answer: DONE and stop. Never output bare JSON or repeat a tool call. Workflow continuation and any human questions are separate tasks controlled by the application.","tools":["POC_V2_QUERY_TOOL"],"enable_human_tool":false}',
    status => 'enabled'
  );
END;
/
-- POC_V2_REVIEW_TOOL: PL/SQL 함수를 호출하는 도구. 입력은 저장된 request_id 하나.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'POC_V2_REVIEW_TOOL',
    attributes => '{"function":"POC_V2_REVIEW_FN","instruction":"Advance or inspect the saved request. Returns a JSON control record containing request_id, revision, state, next_agent, next_task, status, needs_human. Internal errors are not empty business results.","tool_inputs":[{"name":"P_REQUEST_ID","description":"Exact 32-character request_id from delegation. Never CURRENT, never a conversation ID."}]}',
    status => 'enabled'
  );
END;
/
-- POC_V2_REVIEW: 할당된 Task와 Tool로 한 단계를 처리하는 Worker.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'POC_V2_REVIEW',
    attributes => '{"profile_name":"POC_V2_AGENT_PROFILE","role":"Review the saved artifact using the assigned task tool.","enable_human_tool":false}',
    status => 'enabled'
  );
END;
/
-- POC_V2_REVIEW_TASK: 대응 Tool 호출 후 Final Answer: DONE으로 끝내는 Task.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name => 'POC_V2_REVIEW_TASK',
    attributes => '{"instruction":"The delegated input {query} is the original 32-character request ID. Call POC_V2_REVIEW_TOOL once with that ID. After any real tool Observation, this delegated task is complete: output exactly Final Answer: DONE and stop. Never output bare JSON or repeat a tool call. Workflow continuation and any human questions are separate tasks controlled by the application.","tools":["POC_V2_REVIEW_TOOL"],"enable_human_tool":false}',
    status => 'enabled'
  );
END;
/
-- POC_V2_STANDARD_HUMAN_TASK: 실제 후보를 제시하고 사용자 답변을 기다리는 전용 Task.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name => 'POC_V2_STANDARD_HUMAN_TASK',
    attributes => '{"instruction":"Your ONLY task is to obtain a REAL human reply for saved request {query}. Use the available human tool to ask this exact question with its actual candidate options: {human_question}. You MUST call the human tool before giving any final answer. Never invent a human reply. When the real reply arrives, finish with Final Answer: DONE. The application validates and stores the reply; do not call database tools.","tools":[],"enable_human_tool":true}',
    status => 'enabled'
  );
END;
/
-- POC_V2_QUERY_HUMAN_TASK: 실제 후보를 제시하고 사용자 답변을 기다리는 전용 Task.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name => 'POC_V2_QUERY_HUMAN_TASK',
    attributes => '{"instruction":"Your ONLY task is to obtain a REAL human reply for saved request {query}. Use the available human tool to ask this exact question with its actual candidate options: {human_question}. You MUST call the human tool before giving any final answer. Never invent a human reply. When the real reply arrives, finish with Final Answer: DONE. The application validates and stores the reply; do not call database tools.","tools":[],"enable_human_tool":true}',
    status => 'enabled'
  );
END;
/
-- POC_V2_SUPERVISOR: Native 위임을 담당하는 Supervisor.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'POC_V2_SUPERVISOR',
    attributes => '{"profile_name":"POC_V2_AGENT_PROFILE","role":"You supervise ONE saved workflow step per invocation. Read the supplied delegation JSON. Call ORA$DELEGATE_TOOL exactly ONCE with the supplied agent_name, task_name, task_input. All three values must be strings. task_input is ONLY the exact 32-character request ID. Never use an object or array. After the worker returns, immediately finish with Final Answer: DONE. Never delegate twice. The application reads authoritative DB state and invokes later steps. Do not invent observations, human replies, SQL or business results.","enable_human_tool":false,"supervisor":true}',
    status => 'enabled'
  );
END;
/
-- POC_V2_TEAM: Supervisor와 세 종류 Worker를 연결하는 sequential Team.
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name => 'POC_V2_TEAM',
    attributes => '{"agents":[{"name":"POC_V2_STANDARD","task":"POC_V2_STANDARD_TASK"},{"name":"POC_V2_QUERY","task":"POC_V2_QUERY_TASK"},{"name":"POC_V2_REVIEW","task":"POC_V2_REVIEW_TASK"},{"name":"POC_V2_STANDARD","task":"POC_V2_STANDARD_HUMAN_TASK"},{"name":"POC_V2_QUERY","task":"POC_V2_QUERY_HUMAN_TASK"}],"process":"sequential","supervisor_agent":"POC_V2_SUPERVISOR","long_term_memory_length":1}',
    status => 'enabled'
  );
END;
/
DECLARE n NUMBER;BEGIN SELECT COUNT(*) INTO n FROM user_ai_agent_teams WHERE agent_team_name='POC_V2_TEAM' AND status='ENABLED';IF n=1 THEN DBMS_CLOUD_AI_AGENT.DISABLE_TEAM(team_name=>'POC_V2_TEAM');END IF;END;
/
