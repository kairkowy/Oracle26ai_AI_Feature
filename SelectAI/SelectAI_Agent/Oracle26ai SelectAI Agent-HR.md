------------------------------------------------------
### Oracle26ai Select AI Agent 샘플 예제 - JOIN 자동화 
------------------------------------------------------

#### SelectAI Agent 생성 및 실행 순서

  1.AI Agent 생성 - 2.Tool 생성 - 3.Task 생성 - 4.Team 생성 - 5.실행

  지원 Tools : SQL, RAG, WEBSEARCH, NOTIFICATION(EMAIL,SLACK)

#### 테이블에 Annotation 추가

NL2SQL이 쿼리 생성 정확도를 높이기 위하여 HR 샘플테이블에 Annotations을 추가함.

SELECT AI 샘플을 참고하세요.


#### 1. SQL Tool 생성

```sql
-- ==========================================================
-- 1.1 SQL 툴에서 사용할 데이터 프로파일 생성
-- 데이터 프로파일명 : HR_NL2SQL_PROFILE
-- 엔드포인트 : 로컬 Ollama 서비스
-- 오브젝트(HR 테이블) 리스트 추가
-- ==========================================================

BEGIN
  -- 기존 프로파일 있으면 삭제 (없어도 무시)
  BEGIN
    DBMS_CLOUD_AI.DROP_PROFILE(
      profile_name => 'HR_NL2SQL_PROFILE',
      force        => TRUE
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL; 
  END;

  -- 프로파일 생성
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'HR_NL2SQL_PROFILE',
    attributes   => q'!
{
  "provider": "OPENAI",
  "provider_endpoint": "http://service-ollama",
  "model": "gemma3:12b",
  "conversation": false,
  "max_tokens": 1024,
  "temperature": 0.0,
  "comments": false,
  "annotations": true,
  "object_list": [
    {"owner": "HR", "name": "COUNTRIES"},
    {"owner": "HR", "name": "DEPARTMENTS"},
    {"owner": "HR", "name": "EMPLOYEES"},
    {"owner": "HR", "name": "JOBS"},
    {"owner": "HR", "name": "JOB_HISTORY"},
    {"owner": "HR", "name": "LOCATIONS"},
    {"owner": "HR", "name": "REGIONS"}
  ]
}
!',
    status      => 'enabled',
    description => 'HR schema NL2SQL profile for SQL tool'
  );
END;
/

**참고 : "comments":true 및 "annotations": true 옵션은 Annotation 정보를 NL2SQL이 참조할 수있계 활성화 하는 것을 의미함.*

-- ==========================================================
-- 1.2 Tool (SQL) 생성
-- Tool Name : HR_SQL
-- ==========================================================

BEGIN
  -- 기존 툴 있으면 제거
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(
      tool_name => 'HR_SQL',
      force     => TRUE
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
END;
/
-- 새 프로파일 생성
DECLARE
  v_attributes CLOB;
BEGIN
  v_attributes :=
    JSON_OBJECT(
      'tool_type' VALUE 'SQL',
      'tool_params' VALUE JSON_OBJECT(
        'profile_name' VALUE 'HR_NL2SQL_PROFILE'
      ),
      'instruction' VALUE
        'Use this tool for HR schema queries. ' ||
        'Execute the user request and return results first. ' ||
        'Do not use SHOWSQL unless SQL text is explicitly requested. ' ||
        'Preserve the exact meaning of the request. ' ||
        'If asked by job, group by JOB_TITLE. ' ||
        'If asked by department, group by DEPARTMENT_NAME. ' ||
        'For Europe region queries, use REGIONS -> COUNTRIES -> LOCATIONS -> DEPARTMENTS -> EMPLOYEES. ' ||
        'Use JOBS when job title is needed.'
    );

  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name   => 'HR_SQL',
    attributes  => v_attributes,
    description => 'HR schema SQL execution tool'
  );
END;
/
```

#### 2. Task 생성

```sql
-- ==================================================
-- Task 생성
-- Task Name : HR_SQL_TASK
-- ===================================================

BEGIN 
-- 기존 Task 있으면 제거
    DBMS_CLOUD_AI_AGENT.DROP_TASK('HR_SQL_TASK', force => TRUE);
    EXCEPTION 
      WHEN OTHERS THEN NULL;
END;
/

DECLARE
  v_attributes CLOB;
BEGIN
  v_attributes := JSON_OBJECT(
    'instruction' VALUE
      'You are a Korean-speaking HR data analysis agent.' || CHR(10) || CHR(10) ||

      '1. Tool Usage Rules' || CHR(10) ||
      '- For every HR data question, you must call the HR_SQL tool first.' || CHR(10) ||
      '- Always use the tool execution result as the primary evidence.' || CHR(10) ||
      '- Do not answer from general knowledge.' || CHR(10) ||
      '- Do not use SHOWSQL unless the user explicitly asks for SQL.' || CHR(10) || CHR(10) ||

      '2. Single Execution Rule (IMPORTANT)' || CHR(10) ||
      '- Call the HR_SQL tool only once for each user question unless the first call fails.' || CHR(10) ||
      '- Do not repeat the same tool call if a valid result has already been returned.' || CHR(10) ||
      '- Use the first successful execution result as the final evidence.' || CHR(10) || CHR(10) ||

      '3. Query Interpretation Rules' || CHR(10) ||
      '- Pass the user request without changing its meaning.' || CHR(10) ||
      '- Do not convert job-based questions into department-based questions.' || CHR(10) ||
      '- Preserve the original grouping intent (e.g., JOB_TITLE vs DEPARTMENT_NAME).' || CHR(10) || CHR(10) ||

      '4. Output Rules' || CHR(10) ||
      '- If the result contains multiple rows, present all important rows clearly.' || CHR(10) ||
      '- Do not collapse tabular results into a single summary sentence.' || CHR(10) ||
      '- Explain results in Korean.' || CHR(10) || CHR(10) ||

      '5. Exception Handling' || CHR(10) ||
      '- If no rows are returned, say: 데이터가 없습니다.' || CHR(10) ||
      '- If the tool returns an error, briefly report the error in Korean.',

    'tools' VALUE JSON_ARRAY('HR_SQL'),
    'enable_human_tool' VALUE FALSE
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name  => 'HR_SQL_TASK',
    attributes => v_attributes
  );
END;
/

```

#### 3. AI Agent 생성

```sql
-- ================================================
-- Agent Name : HR_SQL_AGENT
-- ================================================

BEGIN
  -- Agent에서 사용할 새 프로파일 기반 Agent 생성
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT(
      agent_name => 'HR_SQL_AGENT',
      force      => TRUE
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'HR_SQL_AGENT',
    attributes => q'!
{
  "profile_name": "HR_NL2SQL_PROFILE",
  "role": "You are a Korean-speaking HR data analysis assistant. Always explain results clearly in Korean."
}
!'
  );
END;
/
```

#### 4. Agent Team 생성

```sql
-- ======================================================
-- Agent team 생성
-- Agent Name : HR_SQL_AGENCY
-- ======================================================

BEGIN
-- 팀 제거
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_TEAM('HR_SQL_AGENCY', force => TRUE);
  EXCEPTION 
    WHEN OTHERS THEN NULL;
  END;

-- 팀 생성 
  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'HR_SQL_AGENCY',
    attributes => q'!
    {
      "agents": [
        { "name": "HR_SQL_AGENT", "task": "HR_SQL_TASK" }
      ],
      "process": "sequential"
    }
    !'
  );
END;
/
```

#### 5. AI Agent 실행

```sql
-- ================================================
-- 5.1 세션 팀 활성화
-- 세션에 Agent temm 지정 후, 자연어로 실행
-- ================================================

-- 지금 세션에 어떤 팀이 설정됐는지 확인

SELECT DBMS_CLOUD_AI_AGENT.GET_TEAM() AS current_team FROM dual;

CURRENT_TEAM
----------------------------------------------------
"HR"."RETURNAGENCY"

-- 세션 팀 활성화
EXECUTE DBMS_CLOUD_AI_AGENT.SET_TEAM('HR_SQL_AGENCY');

-- EXECUTE DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;    -- 세션팀 클리어

-- ================================================
-- 5.2 분석 쿼리 지시 (실행)
-- ================================================

select ai agent '유럽(Europe) 지역 직원의 직무별로 평균 급여 계산해줘';

RESPONSE
--------------------------------------------------------------------------------
영업부서 직원의 평균 연봉은 89,558,823.53원입니다.


-- =====================================================================
-- 5.3. 대화형 Agent 실행 
-- =====================================================================

set serveroutput on

CREATE OR REPLACE PACKAGE my_globals IS
  l_team_cov_id varchar2(4000);
END my_globals;
/
-- Create conversation
DECLARE
  l_team_cov_id varchar2(4000);
BEGIN
-- conversation ID 확인
  l_team_cov_id := DBMS_CLOUD_AI.create_conversation();
  my_globals.l_team_cov_id := l_team_cov_id;
  DBMS_OUTPUT.PUT_LINE('Created conversation with ID: ' || my_globals.l_team_cov_id);
END;
/

-- Created conversation with ID: 4CA59D6F-3B0C-43E2-E063-187B000A8712

-- 대화형 Agent 실행

set serveroutput on
set timing on

DECLARE
  v_response CLOB;
BEGIN
  v_response := DBMS_CLOUD_AI_AGENT.RUN_TEAM(
    team_name   => 'HR_SQL_AGENCY',
    user_prompt => 'query 유럽(Europe) 지역 직원의 직무별로 평균 급여 계산해줘',
    params      => '{"conversation_id": "' || my_globals.l_team_cov_id || '"}'
  );
  DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_response, 4000, 1));
END;
/

-- =====================================================================
-- 6. 세션 팀 반납
-- =====================================================================

EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;

-- =====================================================================
-- 7. 실행 모니터링
-- =====================================================================

set line 300
set pagesize 2000
col INVOCATION_ID format a6
col TOOL_NAME format a20
col INPUT_PREVIEW format a40
col OUTPUT format a40
col tool_output format a40
col START_DATE format a20
col END_DATE format a20
col TASK_NAME format a20

SELECT
  SUBSTR(INVOCATION_ID,1,4) as INVOCATION_ID,
  TOOL_NAME,
  SUBSTR(input, 1, 100)     AS input_preview,
  SUBSTR(output, 1,100)     AS output,
  SUBSTR(tool_output, 1, 100) AS tool_output,
  start_date,
  end_date
FROM user_ai_agent_tool_history
WHERE TOOL_NAME = 'HR_SQL'
ORDER BY start_date DESC
FETCH FIRST 3 ROWS ONLY;

INVOCA TOOL_NAME            INPUT_PREVIEW                            OUTPUT                                   TOOL_OUTPUT                           START_DATE           END_DATE
------ -------------------- ---------------------------------------- ---------------------------------------- ---------------------------------------- -------------------- --------------------
221    HR_SQL               { "TOOL_NAME": "HR_SQL", "QUERY": "What  {"status": "success", "result": "[            26/03/18 07:29:24.84 26/03/18 07:37:40.06
                            is the average salary of employees in th   {                                           5110 +00:00           2399 +00:00
                                                                      "AVG_SALARY" : 8955.88235294117647058


SELECT dbms_lob.substr(output, 4000, 1) AS output_text
FROM   user_ai_agent_tool_history
WHERE  invocation_id = 221;
```
