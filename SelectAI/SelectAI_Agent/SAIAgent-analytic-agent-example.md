----------------------------------------------
통계분석을 위한 SELECT AI Agent 구현 예제 샘플
----------------------------------------------


 ### 사전 준비물 

- 오라클26ai database(Onpremise)
- 테이블 - tour_hist_tbl(제주도 여행자 카드 이력)
- Ollama service : Nginx proxy(80 포트) 구성된 ollama service.
- LLM model : llama3.2, gemma2 등 한글 지원 되는 LLM 모델.

**참고 링크**



### 데이터 준비



### Agent 객체 생성

AI 에이전트를 위한 순서는 데이터 프로파일 생성 -> Tool(SQL) 생성 -> Task 생성 -> Agent 생성 -> Team 생성 -> 실행 순으로 진행됨. 

#### 1. Agent Tool 생성

```sql

-- ==========================================================
-- Step 1-1. Tool에서 사용할 데이터 프로파일 생성
-- 프로파일명 : ANALYSIS_PROFILE
-- 설명 : Ollama 서비스 지전, LLM 지전, 데이터 객체 지정 및 출력 토큰 사이즈, 민감도 등을 지정한다. 
-- ==========================================================

-- 기존 프로파일 있으면 삭제 (없어도 무시)
BEGIN
    DBMS_CLOUD_AI.DROP_PROFILE(
      profile_name => 'ANALYSIS_PROFILE',
      force        => TRUE
    );

  EXCEPTION
    WHEN OTHERS THEN
      NULL; 
END;
/

-- 프로파일 생성
BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'ANALYSIS_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama",
      "model": "gemma2:9b",
      "object_list": [
                      {"owner": "LABADMIN", "name": "TOUR_HIST_TBL"}
                     ],
      "max_tokens": 4096,
      "temperature": 0.1,
     "conversation": "false"
    }',
    status       => 'enabled',
    description  => 'Select AI profile for private Ollama via Nginx proxy'
  );
END;
/

```

```sql

-- ================================================================================
-- 1-2. 쿼리 기반의 Agent Tool(SQL TOOL) 생성
-- Tool Name: SQL_ANALYSIS_TOOL
-- 설명 : 이 툴은 자연어 질문을 SQL 쿼리로 변환하여 데이터베이스를 조회하는 기능을 제공함.
-- ================================================================================

BEGIN
  DBMS_CLOUD_AI_AGENT.DROP_TOOL('SQL_ANALYSIS_TOOL');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name   => 'SQL_ANALYSIS_TOOL',
    attributes  => '{
    	              "tool_type": "SQL",
    	              "tool_params" : {
    	                           	"profile_name":"ANALYSIS_PROFILE"
    	                           	},
                   	   "instruction": "Use this tool whenever the user asks for statistics, aggregation, distribution, totals, ranking, trends, or grouped analysis. Generate SQL only against approved objects in the profile, execute it, and return the actual database result."
    }',
    description => 'Queries the database for TOUR_HIST_TBL.  Use this tool for SQL-based analysis'
  );
END;
/

```

2. Task 생성

```sql
-- =================================================================================
-- 2. Task 생성
-- Task name : ANALYSIS_TASK
-- 설명 : 작업은 도구 선택(어떤 도구를 사용할지), 매개변수 매핑(어떤 파라미터를 전달할지) 및 
-- 실행 정책을 안내하며, 하위 단계에서 읽고 요약할 수 있는 결과를 생성한다
-- =================================================================================

BEGIN
  DBMS_CLOUD_AI_AGENT.DROP_TASK('ANALYSIS_TASK');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

DECLARE
  v_attributes CLOB;
BEGIN
  v_attributes := JSON_OBJECT(
    'instruction' VALUE
                 'You are a Korean-speaking data analysis agent. deal with customer inquiry based on user request:{query}' ||
                 'For statistical or aggregation questions, you MUST use SQL_ANALYSIS_TOOL first.'||
                 'Query only approved database objects from the profile. '||
                 'Do not answer from general knowledge. Do not ask the user for clarification unless the request is impossible.'||
                 'Execute SQL_ANALYSIS_TOOL, read the query result, and then summarize the actual result in Korean.'||
                 'If no rows are returned, say that no data was found. If the required columns do not exist, explicitly say which columns are missing.',
    'enable_human_tool' VALUE false    
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name  => 'ANALYSIS_TASK',
    attributes => v_attributes
  );
END;
/
```


    'You are a customer service agent. deal with customer inquiry based on user request:{query}' ||
    'For statistical or aggregation questions, use SQL_ANALYSIS_TOOL' ||
    'Query only approved database objects from the profile. Summarize the result clearly in Korean.'||
    'If the requested metric or column does not exist in TOUR_HIST_TBL, explicitly say so.',

    "instruction": "You are a Korean-speaking data analysis agent. For any query asking about count, sum, average, distribution, ranking, by-category, by-industry, trend, or statistics, you MUST use SQL_ANALYSIS_TOOL first. Query only approved database objects from the profile. Do not answer from general knowledge. Do not ask the user for clarification unless the request is impossible. Execute SQL_ANALYSIS_TOOL, read the query result, and then summarize the actual result in Korean. If no rows are returned, say that no data was found. If the required columns do not exist, explicitly say which columns are missing.",

    "instruction": "You are a Korean-speaking data analysis agent. For any query asking about count, sum, average, distribution, ranking, by-category, by-industry, trend, or statistics, you MUST use SQL_ANALYSIS_TOOL first. Do not answer from general knowledge. Do not ask the user for clarification unless the request is impossible. Execute SQL_ANALYSIS_TOOL, read the query result, and then summarize the actual result in Korean. If no rows are returned, say that no data was found. If the required columns do not exist, explicitly say which columns are missing.",


3. Agent 생성

```sql
-- ================================================================
-- 3. Task 생성
-- Agent name : ANALYTIC_BOT
-- ================================================================

BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('ANALYTIC_BOT', force => TRUE);
      EXCEPTION
      WHEN OTHERS THEN NULL;
END;
/

BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'ANALYTIC_BOT',
    attributes => '{
                    "profile_name": "ANALYSIS_PROFILE",
                    "role": "You are a BOT agent for data analysis expert . always provide a clear and user-friendly explanation in Korean."
                  }'
  );
END;
/

```

4. Agent 팀 생성

```sql
-- ===============================================
-- Step 4.1 : Team 생성
-- 설명: 에이전트와 Task를 연결하여 팀 구성
-- Team Name : ANALYTIC_TEAM
-- ===============================================

BEGIN 
	DBMS_CLOUD_AI_AGENT.DROP_TEAM('ANALYTIC_TEAM', force => TRUE);
    EXCEPTION 
    WHEN OTHERS THEN NULL;
END;
/

BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'ANALYTIC_TEAM',
    attributes => '{
                    "agents": [
                      {
                        "name": "ANALYTIC_BOT",
                        "task": "ANALYSIS_TASK"
                      }
                    ],
                    "process": "sequential"
                  }'
  );
END;
/

-- =====================================================================
-- Step 4.2: Team 활성화
-- 설명: 현재 데이터베이스 세션에서 사용할 팀 지정
-- =====================================================================

EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('ANALYTIC_TEAM');

-- 활성화된 팀 확인
SELECT DBMS_CLOUD_AI_AGENT.GET_TEAM() AS ACTIVE_TEAM FROM DUAL;

ACTIVE_TEAM
-------------------------------------------------------------------------------------------
"LABADMIN"."ANALYTIC_TEAM"

```

**중요: SET_TEAM은 세션 단위로 적용됩니다. 새로운 SQL 세션을 열면 다시 설정해야 합니다.**

#### 5. Agent 실행

```sql
-- =====================================================================
-- 5.1. 세션에 Agent team 설정
-- =====================================================================

EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('ANALYTIC_TEAM');

-- =====================================================================
-- 5.2. conversation ID 확인
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
  l_team_cov_id := DBMS_CLOUD_AI.create_conversation();
  my_globals.l_team_cov_id := l_team_cov_id;
  DBMS_OUTPUT.PUT_LINE('Created conversation with ID: ' || my_globals.l_team_cov_id);
END;
/

-- Created conversation with ID: 4CA59D6F-3B0C-43E2-E063-187B000A8712

-- =====================================================================
-- 5.3. 대화형 Agent 실행
-- =====================================================================

set serveroutput on
set timing on

DECLARE
  v_response CLOB;
BEGIN
  v_response := DBMS_CLOUD_AI_AGENT.RUN_TEAM(
    team_name   => 'ANALYTIC_TEAM',
    user_prompt => 'query 업종별 카드결재 금액을 합계내주고 상위업종순으로 보여줘?',
    params      => '{"conversation_id": "' || my_globals.l_team_cov_id || '"}'
  );
  DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_response, 4000, 1));
END;
/

-- =====================================================================
-- 5.4 세션 팀 반납
-- =====================================================================

EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;


```


6. Agent Object 모니터링

```sql
-- =====================================================================
-- 프로파일 목록 조회
-- =====================================================================
set line 200
col ATTRIBUTE_NAME format a30
col attribute_value format a100

SELECT p.profile_name,
       p.status,
       CAST(p.created AS DATE) AS created,
       a.attribute_name,
       DBMS_LOB.SUBSTR(a.attribute_value, 4000, 1) AS attribute_value
FROM   user_cloud_ai_profiles p
JOIN   user_cloud_ai_profile_attributes a
       USING (profile_id)
WHERE p.PROFILE_NAME = 'ANALYSIS_PROFILE'
ORDER BY p.profile_name, a.attribute_name;

PROFILE_NAME                   STATUS                   CREATED  ATTRIBUTE_NAME                 ATTRIBUTE_VALUE
------------------------------ ------------------------ -------- ------------------------------ ----------------------------------------------------------------------------------------------------
ANALYSIS_PROFILE               ENABLED                  26/03/10 conversation                   false
ANALYSIS_PROFILE               ENABLED                  26/03/10 max_tokens                     4096
ANALYSIS_PROFILE               ENABLED                  26/03/10 model                          gemma2:9b
ANALYSIS_PROFILE               ENABLED                  26/03/10 object_list                    [{"owner":"LABADMIN","name":"tour_hist_tbl"}]
ANALYSIS_PROFILE               ENABLED                  26/03/10 provider_endpoint              http://service-ollama
ANALYSIS_PROFILE               ENABLED                  26/03/10 temperature                    0.1

-- =====================================================================
-- tool 생성 확인
-- =====================================================================

set line 200
col tool_name format a30
col description format a40
col attribute_name format a30
col attribute_value format a100

SELECT t.tool_name,
       t.description,
       t.status,
       a.attribute_name,
       DBMS_LOB.SUBSTR(a.attribute_value, 4000, 1) AS attribute_value,
       CAST(a.last_modified AS DATE) AS last_modified
FROM   user_ai_agent_tools t
JOIN   user_ai_agent_tool_attributes a
       USING (tool_id)
WHERE t.TOOL_NAME = upper('SQL_ANALYSIS_TOOL')
ORDER  BY t.tool_name, a.attribute_name;
TOOL_NAME                      DESCRIPTION                              STATUS                   ATTRIBUTE_NAME
------------------------------ ---------------------------------------- ------------------------ ------------------------------
ATTRIBUTE_VALUE                                                                                      LAST_MOD
---------------------------------------------------------------------------------------------------- --------
SQL_ANALYSIS_TOOL              Queries the database for tour_hist_tbl.  ENABLED                  instruction
                               Use this tool when you need to query ana
This tool is used to work with SQL queries using natural language. Input should be a natural languag 26/03/10
e query about data or database operations. The tool behavior depends on the configured action: RUNSQ
L - generates and executes the SQL query returning actual data; SHOWSQL - generates and displays the
 SQL statement without executing it; EXPLAINSQL - generates SQL and provides a natural language expl
anation of what the query does. Always provide clear, specific questions about the data you want to
retrieve or analyze.

SQL_ANALYSIS_TOOL              Queries the database for tour_hist_tbl.  ENABLED                  tool_params
                               Use this tool when you need to query ana
{"profile_name":"ANALYSIS_PROFILE"}                                                                  26/03/10

SQL_ANALYSIS_TOOL              Queries the database for tour_hist_tbl.  ENABLED                  tool_type
                               Use this tool when you need to query ana
SQL                                                                                                  26/03/10

-- ===============================================
-- tool 실행 로그 확인
-- tool이 실제로 호출되었는지 확인
-- ===============================================
col CONVERSATION_PROMPT_ID format a30
col CONVERSATION_ID format a30
col PROMPT format a50

SELECT 
    CONVERSATION_PROMPT_ID,
    CONVERSATION_ID,
    PROMPT,
    PROMPT_RESPONSE,
    PROMPT_ACTION,
    CREATED
FROM USER_CLOUD_AI_CONVERSATION_PROMPTS
ORDER BY CREATED DESC
FETCH FIRST 5 ROWS ONLY;
CONVERSATION_PROMPT_ID         CONVERSATION_ID                PROMPT                                             PROMPT_RESPONSE
------------------------------ ------------------------------ -------------------------------------------------- --------------------------------------------------------------------------------
PROMPT_ACTION                     CREATED
--------------------------------- ---------------------------------------------------------------------------
4CA59D6F-3B22-43E2-E063-187B00 4CA59D6F-3B1C-43E2-E063-187B00 query 업종별 카드결재 금액 통계내줘?               TOUR_HIST_TBL 테이블에서 '업종'을 기준으로 카드 결제 금액을
0A8712                         0A8712                                                                            '
AGENT                             26/03/10 05:39:56.129478 +00:00

4CA59D6F-3B21-43E2-E063-187B00 4CA59D6F-3B1E-43E2-E063-187B00                                                    Thought: 고객님께서 업종별 카드 결제 금액 통계를 원하신다
0A8712                         0A8712
CHAT                              26/03/10 05:39:56.125511 +00:00


-- ===============================================
-- Task에 연결된 tool 목록 확인
-- ===============================================

SELECT t.owner,
       t.task_name,
       t.status,
       JSON_OBJECTAGG(a.attribute_name VALUE DBMS_LOB.SUBSTR(a.attribute_value, 4000, 1)) AS task_config
FROM   dba_ai_agent_tasks t
LEFT JOIN dba_ai_agent_task_attributes a
       ON t.task_id = a.task_id
WHERE t.TASK_NAME = upper('ANALYSIS_TASK')
GROUP BY t.owner, t.task_name, t.status
ORDER BY t.owner, t.task_name;


SELECT T.TASK_NAME,
       T.STATUS,
       JSON_OBJECTAGG(A.ATTRIBUTE_NAME VALUE DBMS_LOB.SUBSTR(A.ATTRIBUTE_VALUE, 4000, 1)) AS TASK_CONFIG
FROM   USER_AI_AGENT_TASKS T
LEFT JOIN USER_AI_AGENT_TASK_ATTRIBUTES A
       ON T.TASK_ID = A.TASK_ID
WHERE T.TASK_NAME = UPPER('ANALYSIS_TASK')
GROUP BY T.TASK_NAME, T.STATUS
ORDER BY T.TASK_NAME;

-- ===============================================
-- Agent 목록 조회
-- ===============================================

SELECT 
    AGENT_NAME,
    DESCRIPTION,
    CREATED
FROM USER_AI_AGENTS
WHERE AGENT_NAME = upper('ANALYTIC_BOT');

-- ===============================================
-- Team 정보 확인
-- ===============================================

SELECT t.owner,
       t.agent_team_name,
       t.status,
       JSON_OBJECTAGG(
         a.attribute_name
         VALUE DBMS_LOB.SUBSTR(a.attribute_value, 4000, 1)
       ) AS team_config
FROM   dba_ai_agent_teams t
LEFT JOIN dba_ai_agent_team_attributes a
       ON t.owner           = a.owner
      AND t.agent_team_name = a.agent_team_name
WHERE t.AGENT_TEAM_NAME = upper('ANALYTIC_TEAM')
GROUP BY t.owner, t.agent_team_name, t.status
ORDER BY t.owner, t.agent_team_name;

SELECT T.AGENT_TEAM_NAME,
       T.STATUS,
       JSON_OBJECTAGG(
         A.ATTRIBUTE_NAME
         VALUE DBMS_LOB.SUBSTR(A.ATTRIBUTE_VALUE, 4000, 1)
       ) AS TEAM_CONFIG
FROM   USER_AI_AGENT_TEAMS T
LEFT JOIN USER_AI_AGENT_TEAM_ATTRIBUTES A
       ON T.AGENT_TEAM_NAME = A.AGENT_TEAM_NAME
WHERE T.AGENT_TEAM_NAME = UPPER('ANALYTIC_TEAM')
GROUP BY T.AGENT_TEAM_NAME, T.STATUS
ORDER BY T.AGENT_TEAM_NAME;
```