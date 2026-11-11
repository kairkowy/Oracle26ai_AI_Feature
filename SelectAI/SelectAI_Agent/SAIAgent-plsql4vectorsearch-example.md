# Select AI Agent: PL/SQL 함수 기반 벡터 검색

> **온프레미스 기준**: Oracle AI Database 26ai의 지원 RU와 대상 PDB에서 실행합니다. 먼저 [공통 환경 구성](./OnPremises_Setup.md)에서 버전·패키지·권한·ACL·LLM 연결을 확인합니다. 엔드포인트·모델·스키마·테이블은 실제 환경에 맞게 변경합니다. 아래 SQL은 실습용이며, 생성된 객체를 정리한 후 재실행합니다.

기존 RAG_TBL_V 테이블을 검색하는 PL/SQL 함수를 Tool로 등록합니다. 내장 RAG 도구의 CREATE_VECTOR_INDEX 파이프라인을 새로 만드는 예제는 아닙니다.

## 사전 준비

- 실습 스키마에 RAG_TBL_V가 있어야 하며, 아래 함수는 문서번호·청크ID·문서내용(CLOB)·벡터(VECTOR) 컬럼을 사용합니다. BLOB·이미지 저장소는 텍스트 추출과 컬럼 변환을 별도로 구현해야 합니다.
- MULTILINGUAL_E5_SMALL 임베딩 모델이 같은 스키마에 적재되어 있어야 합니다. 문서 벡터와 질의 벡터의 모델·전처리·차원·거리 척도를 일치시킵니다. E5처럼 질의·문서 접두어를 사용하는 모델은 기존 적재 방식과 동일하게 적용합니다.
- 사용자 정의 저장 함수를 생성할 CREATE PROCEDURE 권한이 필요합니다. 타 스키마 테이블·함수·모델을 사용하면 직접 권한과 스키마 한정 이름을 확인합니다.

```sql
SELECT column_name, data_type FROM user_tab_columns
WHERE table_name = 'RAG_TBL_V' ORDER BY column_id;
SELECT COUNT(*) AS chunk_count FROM RAG_TBL_V;
SELECT model_name FROM user_mining_models
WHERE model_name = 'MULTILINGUAL_E5_SMALL';
```

이 문서는 원본 문서와 벡터 데이터를 배포하지 않습니다. 기존 데이터 준비 예시는 [벡터 검색 실습 저장소](https://github.com/kairkowy/handon-labs-for-vector-search)에서 확인할 수 있으며, 위 컬럼 구조와 맞는지 점검합니다.

## 1. 벡터 검색 함수 생성

```sql
-- PL/SQL Tool 생성 위한 PL/SQL 함수 생성.
-- 사용자 입력 문장을 기반으로 벡터검색 결과 반환하는 함수임.

-- CREATE OR REPLACE는 기존 함수를 교체합니다.

CREATE OR REPLACE FUNCTION VECTOR_SEARCH (
    p_query IN VARCHAR2
) RETURN CLOB
AUTHID DEFINER
IS
    l_result CLOB;
BEGIN
    IF TRIM(p_query) IS NULL THEN
      RETURN TO_CLOB('[]');
    END IF;

    SELECT JSON_ARRAYAGG(
             JSON_OBJECT(
               'document_id' VALUE t.doc_id,
               'chunk_id' VALUE t.chunk_id,
               'distance' VALUE t.distance_value,
               'text' VALUE DBMS_LOB.SUBSTR(t.chunk_text, 2000, 1)
               RETURNING CLOB
             ) ORDER BY t.distance_value RETURNING CLOB
           )
    INTO l_result
    FROM (
      SELECT v."문서번호" AS doc_id, v."청크ID" AS chunk_id,
             v."문서내용" AS chunk_text,
             VECTOR_DISTANCE(
               v."벡터",
               VECTOR_EMBEDDING(MULTILINGUAL_E5_SMALL USING p_query AS data),
               COSINE
             ) AS distance_value
      FROM RAG_TBL_V v
      WHERE v."벡터" IS NOT NULL
      ORDER BY distance_value
      FETCH FIRST 5 ROWS ONLY
    ) t;

    RETURN COALESCE(l_result, TO_CLOB('[]'));
END;
/
SHOW ERRORS FUNCTION VECTOR_SEARCH

-- Agent를 연결하기 전에 함수 자체의 검색 결과를 확인합니다.
SET LONG 20000
SELECT VECTOR_SEARCH('문서의 주요 주제를 찾아줘') AS retrieved_chunks FROM dual;
```

상위 5개를 반환하는 예제이므로 검색 결과가 있다는 사실만으로 관련성이 보장되지는 않습니다. 실제 자료에 맞는 거리 임계값을 정하려면 관련·무관 질의의 거리를 비교해 조정합니다. 위 함수는 문서 내용의 첫 2000자만 전달하므로 중요한 근거가 잘리지 않는지도 확인합니다.

## 2. Agent Tool 생성

```sql
-- PL/SQL 기반의 Agent Tool(VECTOR_SEARCH_TOOL) 생성

BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name   => 'VECTOR_SEARCH_TOOL',
    attributes  => '{
      "instruction": "Use this tool only to retrieve top 5 relevant chunks from RAG_TBL_V. This tool requires exactly one parameter: p_query (string). Return only retrieved context text. Do not summarize. Do not provide the final answer.",
      "function": "VECTOR_SEARCH"
    }',
    description => 'Vector search context tool'
  );
END;
/

```

지침은 이 예제에서 영어로 작성하고 최종 응답 언어는 한국어로 지정합니다. 실제 동작은 모델의 지침 준수·도구 호출 능력에 따라 확인합니다.

## 3. Task 생성

```sql
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
    'tools' VALUE JSON_ARRAY('VECTOR_SEARCH_TOOL'),
    'enable_human_tool' VALUE false
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name  => 'INFO_SERVICE_TASK',
    attributes => v_attributes
  );
END;
/
```

## 4. Agent 생성

```sql
BEGIN
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

## 5. Agent 팀 생성

```sql
BEGIN

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

## 6. 실행과 근거 확인

```sql
EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('RETURN_AGENCY');
SELECT DBMS_CLOUD_AI_AGENT.GET_TEAM() AS current_team FROM dual;
SELECT AI AGENT 제공된 문서의 주요 내용을 문서번호와 청크ID를 포함해 요약해줘;
EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
```

같은 질문의 함수 직접 호출 결과와 도구 이력을 비교합니다. 대화 ID를 재사용하는 RUN_TEAM 예제와 전체 CLOB 출력은 [공통 실행 안내](./OnPremises_Setup.md#4-실행과-대화-문맥)를 참고합니다.

함수 직접 호출 결과의 document_id·chunk_id·text와 에이전트 답변을 비교합니다. 근거가 없으면 답변에서 근거 부족을 표시해야 합니다. 모델이 생성한 법령명·수치 등을 검증된 결과처럼 고정해 수록하지 않습니다.

Tool 이력은 [공통 모니터링](./OnPremises_Setup.md#5-실행-이력과-문제-확인)에서 tool_name = 'VECTOR_SEARCH_TOOL'로 확인합니다. 함수는 DEFINER 권한으로 실행되므로 함수가 참조할 데이터 범위를 명확히 한정합니다.

참고: [Oracle 사용자 정의 Tool 예제](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/examples-using-select-ai-agent1.html), [공식 Agent 패키지](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai-agent-pl-sql-package.html).

## 실습 객체 정리

공유 객체가 아닌지 확인한 후 실행합니다. 원본 테이블은 삭제하지 않습니다.

```sql
BEGIN
  DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
  DBMS_CLOUD_AI_AGENT.DROP_TEAM('RETURN_AGENCY', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TASK('INFO_SERVICE_TASK', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TOOL('VECTOR_SEARCH_TOOL', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_AGENT('INFOSERVICE_AGENT', force => TRUE);
  DBMS_CLOUD_AI.DROP_PROFILE('INFOSERVICE_PROFILE', force => TRUE);
END;
/
```

VECTOR_SEARCH 함수, RAG_TBL_V 테이블과 임베딩 모델은 위 정리에서 삭제하지 않습니다.
