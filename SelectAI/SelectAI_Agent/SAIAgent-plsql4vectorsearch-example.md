-------------------------------------------------------------------------------
### PL/SQL Funtion(Vector Search)을 이용한 Select AI Agent 예제 
-------------------------------------------------------------------------------

이 예제 샘플은 Select AI Agent에서 vector search 파이프라인 기능으로 임베딩된 벡터 테이블의 데이터를 Select AI Agent에 통합하는 방법을 제공하는 샘플임.

### 사전 준비물 

- 오라클26ai database(Onpremise)
- 벡터 테이블 - Blob 또는 Varchar 컬럼에 있는 텍스트(또는 이미지)를 임베딩 한 데이블.
- Ollama service : Nginx proxy(80 포트) 구성된 ollama service.
- LLM model : llama3.2, gemma2 등 한글 지원 되는 LLM 모델.

**참고 링크**

- 벡터 테이블(rag_tbl_v) : https://github.com/kairkowy/handon-labs-for-vector-search/blob/main/Configuration/similarity_search_config.sql
- 임베딩 : https://github.com/kairkowy/handon-labs-for-vector-search/blob/main/similarity_search/2-1.RAG_DOC.ipynb
- Ollama-Nginx 서비스 구성 : https://github.com/kairkowy/handon-labs-for-vector-search/blob/main/SelectAI/SelectAI_Ollama_Proxy_Config.md


### Agent 객체 생성

#### 1. 벡터쿼리 Function 생성

```sql
-- PL/SQL Tool 생성 위한 PL/SQL 함수 생성.
-- 사용자 입력 문장을 기반으로 벡터검색 결과 반환하는 함수임.

##DROP FUNCTION vector_search

CREATE OR REPLACE FUNCTION VECTOR_SEARCH (
    p_query IN VARCHAR2
) RETURN CLOB
IS
    l_result CLOB;
BEGIN
    SELECT COALESCE(
             XMLCAST(
               XMLAGG(
                 XMLELEMENT(
                   e,
                   '문서번호: ' || t."문서번호" || ', 청크ID: ' || t."청크ID" || CHR(10) ||
                   REGEXP_REPLACE(
                     REGEXP_REPLACE(
                       DBMS_LOB.SUBSTR(t."문서내용", 1200, 1),
                       '[[:cntrl:]]',' '
                     ),
                     '[^가-힣a-zA-Z0-9 ]',' '
                   ) || CHR(10) ||
                   '------------------------' || CHR(10)
                 )
               ) AS CLOB
             ),
             TO_CLOB('No matches.')
           )
    INTO l_result
    FROM (
        SELECT v."문서번호",
               v."청크ID",
               v."문서내용"
        FROM RAG_TBL_V v
        ORDER BY VECTOR_DISTANCE(
                 v."벡터",
                 VECTOR_EMBEDDING(MULTILINGUAL_E5_SMALL USING p_query AS data),
                 COSINE
               )
        FETCH FIRST 5 ROWS ONLY
    ) t;

    RETURN l_result;
END;
/

-- PL/SQL vector_search 함수 테스트

ACCEPT user_q PROMPT '질문을 입력하세요:'

공공기관 소프트웨어 분리발주 대상 사업 법적근거는?

SET SERVEROUTPUT ON;

DECLARE
    v_result CLOB;
BEGIN
    v_result := VECTOR_SEARCH('&user_q');
    DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_result, 4000, 1));  -- 필요 시 4000 늘려서 여러 번 출력 가능
END;
/

```

#### 2. Agent Tool 생성

```sql
-- PL/SQL 기반의 Agent Tool(VECTOR_SEARCH_TOOL) 생성

BEGIN
  DBMS_CLOUD_AI_AGENT.DROP_TOOL('VECTOR_SEARCH_TOOL');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name   => 'VECTOR_SEARCH_TOOL',
    attributes  => '{
      "instruction": "Use this tool only to retrieve top 5 relevant chunks from RAG_TBL_V. This tool requires exactly one parameter: query (string). Return only retrieved context text. Do not summarize. Do not provide the final answer.",
      "function": "VECTOR_SEARCH"
    }',
    description => 'Vector search context tool'
  );
END;
/

```
***주의 : attribute에 들어가는 Instruction, role등은 영문으로 지정해야 정확한 실행이 가능함. 한글 지시어는 작동이 않될 수 있음.***

#### 3. Task 생성

```sql
BEGIN
  DBMS_CLOUD_AI_AGENT.DROP_TASK('INFO_SERVICE_TASK');
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

DECLARE
  v_attributes CLOB;
BEGIN
  v_attributes := JSON_OBJECT(
    'instruction' VALUE
             'You are an information retrieval agent. Use the provided information to answer the user request: {query}. ' ||
              'You must first call VECTOR_SEARCH_TOOL to retrieve relevant context. ' ||
              'After retrieving the context, generate the final answer in Korean. ' ||
              'Do not end the response by returning the tool output directly. ' ||
              'Always organize the final response in the following format: ' ||
              '1) Summary ' ||
              '2) Evidence (문서번호, 청크ID) ' ||
              '3) Additional checks. ' ||
               'If the requested information is not found in the context, explicitly state "Insufficient evidence". ' ||
              'The final answer must end with natural language sentences.',
    'enable_human_tool' VALUE false    
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name  => 'INFO_SERVICE_TASK',
    attributes => v_attributes
  );
END;
/
```

#### 4. Agent 생성

```sql
BEGIN
  BEGIN
  -- 있으면 삭제 (force => true)
  DBMS_CLOUD_AI.DROP_PROFILE(
    profile_name => 'INFOSERVICE_PROFILE',
    force        => TRUE
  );
  END;

  -- 생성
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'INFOSERVICE_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama",
      "model": "gemma2:9b",
      "conversation": true
    }',
    status       => 'enabled'
  );
END;
/


BEGIN
  BEGIN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT('INFOSERVICE_AGENT', force => TRUE);
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'INFOSERVICE_AGENT',
    attributes => q'{
                {
                  "profile_name": "INFOSERVICE_PROFILE",
                  "role": "You are a RAG-based information retrieval agent. Always retrieve relevant context using the VECTOR_SEARCH_TOOL before answering. Use the retrieved context as the primary evidence to generate the final response in Korean. always provide a clear and user-friendly explanation."
                }
    }'
  );
END;
/
```

#### 5. Agent 팀 생성

```sql
BEGIN
  -- 팀 제거
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_TEAM('RETURN_AGENCY', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- 팀 생성 
  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'RETURN_AGENCY',
    attributes => '{
      "agents": [
        { "name": "INFOSERVICE_AGENT", "task": "INFO_SERVICE_TASK" }
      ],
      "process": "sequential"
    }'
  );
END;
/

```

#### 6. Agent 실행

```sql

-- 1. 세션에 Agent team 설정

-- EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;

EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('RETURN_AGENCY');

-- 2. conversation ID 확인

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

Created conversation with ID: 4CA2DA2C-C33D-32E8-E063-187B000A14BB

-- 3. 대화형 Agent 실행
set serveroutput on
set timing on

DECLARE
  v_response CLOB;
BEGIN
  v_response := DBMS_CLOUD_AI_AGENT.RUN_TEAM(
    team_name   => 'RETURN_AGENCY',
    user_prompt => 'query 공공기관 소프트웨어 분리발주 대상사업 관련 법률근거는?',
    params      => '{"conversation_id": "' || my_globals.l_team_cov_id || '"}'
  );
  DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_response, 4000, 1));
END;
/

공공기관 소프트웨어 분리발주 대상 사업 관련 법률 근거는 정보통신망법 제2조 제1항과 제10조 제1항입니다. 정보통신망법 제2조 제1항은 공공기관의 사업을
정의하고, 제10조 제1항은 분리발주를 할 수 있는 사업을 규정하고 있습니다.

경   과: 00:00:47.29

```

#### 7. 세션의 Agent team 종료(close)

```sql
EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
```

#### 8. Select AI 실행 모니터링

```sql

-- Tool생성 확인
set line 200
col tool_name format a30
col description format a40
col attribute_name format a30
col attribute_value format a100

SELECT t.tool_name,
       t.description,
       t.status,
       a.attribute_name,
       DBMS_LOB.SUBSTR(a.attribute_value, 4000, 1) AS attribute_value
FROM   user_ai_agent_tools t
JOIN   user_ai_agent_tool_attributes a
       USING (tool_id)
WHERE t.TOOL_NAME = upper('VECTOR_SEARCH_TOOL')
ORDER BY t.tool_name, a.attribute_name;

TOOL_NAME                      DESCRIPTION                              STATUS                   ATTRIBUTE_NAME
------------------------------ ---------------------------------------- ------------------------ ------------------------------
ATTRIBUTE_VALUE
----------------------------------------------------------------------------------------------------
VECTOR_SEARCH_TOOL             Vector search context tool               ENABLED                  function
VECTOR_SEARCH

VECTOR_SEARCH_TOOL             Vector search context tool               ENABLED                  instruction
Use this tool only to retrieve top 5 relevant chunks from RAG_TBL_V. This tool requires exactly one
parameter: query (string). Return only retrieved context text. Do not summarize. Do not provide the

-- Tool history 조회
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
WHERE TOOL_NAME = 'VECTOR_SEARCH_TOOL'
ORDER BY start_date DESC
FETCH FIRST 3 ROWS ONLY;

-- Tool 호출 이력 조회

SELECT 
    TOOL_NAME,              -- 실행된 tool 이름
    INPUT,                  -- tool에 전달된 입력 (CLOB)
    LENGTH(OUTPUT) AS OUTPUT_LENGTH,  -- 출력 길이 (바이트)
    TOOL_OUTPUT,            -- tool의 실행 결과 (CLOB)
    START_DATE              -- tool 실행 시작 시각
FROM USER_AI_AGENT_TOOL_HISTORY
ORDER BY START_DATE DESC;

-- 최근 10개만 조회
SELECT 
    TOOL_NAME,
    SUBSTR(INPUT, 1, 100) AS INPUT_PREVIEW,
    LENGTH(OUTPUT) AS OUTPUT_LENGTH,
    SUBSTR(TOOL_OUTPUT, 1, 200) AS OUTPUT_PREVIEW,
    START_DATE,
    END_DATE,
    (END_DATE - START_DATE) * 24 * 3600 AS DURATION_SECONDS  -- 실행 시간 (초)
FROM USER_AI_AGENT_TOOL_HISTORY
ORDER BY START_DATE DESC
FETCH FIRST 10 ROWS ONLY;
```

#### 9. ollama 서비스 모니터링

ollama 서비스를 디버그 모드로 실행하면 LLM과 Agent 사이의 API 응답 요청, 답변 상황을 모니터링하면 진행상황을 보다 직관적으로 모니터링 할 수 있음.

