# Select AI Agent: SQL·RAG 도구 실습

> **온프레미스 기준**: Oracle AI Database 26ai의 지원 RU와 대상 PDB에서 실행합니다. 먼저 [공통 환경 구성](./OnPremises_Setup.md)에서 버전·패키지·권한·ACL·LLM 연결을 확인합니다. 엔드포인트·모델·스키마·테이블은 실제 환경에 맞게 변경합니다. 아래 SQL은 실습용이며, 생성된 객체를 정리한 후 재실행합니다.

이 문서는 SQL 도구와 내장 RAG 도구를 각각 구성합니다. 공통 프로파일 설정은 [Oracle 제공자 안내](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-your-ai-provider-and-ai-models.html), 객체 API는 [26ai Agent 패키지 문서](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-ai-agent-pl-sql-package.html)를 기준으로 합니다.

## 1. SQL 도구

먼저 LABADMIN의 TOUR_HIST_TBL_ENG 데이터가 준비되어 있어야 합니다. 이 문서는 원본 관광 데이터를 배포하지 않습니다. 데이터 소유자가 다르면 object_list와 아래 점검 SQL을 함께 변경합니다.

```sql
SELECT column_name, data_type FROM all_tab_columns
WHERE owner = 'LABADMIN' AND table_name = 'TOUR_HIST_TBL_ENG'
ORDER BY column_id;
SELECT COUNT(*) AS row_count FROM LABADMIN.TOUR_HIST_TBL_ENG;
```

### 1.1. AI Agent 생성

```sql

-- Agent용 프로파일 생성

BEGIN
  -- 생성
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'AGENT_OLLAMA_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama",
      "model": "qwen2.5-coder:7b",
      "conversation": false
    }',
    status       => 'enabled'
  );
END;
/

-- Agent 생성
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'SQL_TOOL_AGENT',
    attributes => '{
      "profile_name": "AGENT_OLLAMA_PROFILE",
      "role": "You are a database data analysis assistant. Use the assigned tools and answer in Korean."
    }'
  );
END;
/
```

### 1.2. Tool 생성

```sql

-- SQL 도구용 프로파일 생성

BEGIN

  -- 프로파일 생성
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'NL2SQL_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama",
      "model": "qwen2.5-coder:7b",
      "conversation": false,
      "enforce_object_list": true,
      "object_list": [
        {"owner": "LABADMIN", "name": "TOUR_HIST_TBL_ENG"}
      ]
    }');
END;
/

-- SQL 툴 생성

BEGIN

  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name  => 'SQL',
    attributes => '{"tool_type": "SQL","tool_params": { "profile_name": "NL2SQL_PROFILE" }
    }'
  );
END;
/

```

### 1.3. Task 생성

```sql
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name  => 'SQL_ONLY_TASK',
    attributes => '{
      "tools": ["SQL"],
      "instruction": "Use SQL to query TOUR_HIST_TBL_ENG for the user request: {query}. Answer in Korean using only the query result. Report errors or missing data without guessing.",
      "enable_human_tool": false
    }'
  );
END;
/
```

### 1.4. Team 생성

```sql

BEGIN

  -- 팀 생성
  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'RETURNAGENCY',
    attributes => '{
      "agents": [
        { "name": "SQL_TOOL_AGENT", "task": "SQL_ONLY_TASK" }
      ],
      "process": "sequential"
    }'
  );
END;
/

```

### 1.5. AI Agent 실행

```sql
EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('RETURNAGENCY');
SELECT DBMS_CLOUD_AI_AGENT.GET_TEAM() AS current_team FROM dual;
SELECT AI AGENT 카드 이용금액을 성별로 구분해 합계를 알려줘;
EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
```

같은 질문의 원본 SQL 결과와 도구 이력을 비교합니다. 대화 ID를 재사용하는 RUN_TEAM 예제와 전체 CLOB 출력은 [공통 실행 안내](./OnPremises_Setup.md#4-실행과-대화-문맥)를 참고합니다.

```sql
-- 에이전트 결과 비교용 SQL. 실제 컬럼 정의와 금액 단위를 먼저 확인합니다.
SELECT gender, SUM(card_tr_amount) AS total_amount
FROM LABADMIN.TOUR_HIST_TBL_ENG
GROUP BY gender
ORDER BY gender;
```

## 2. 내장 RAG 도구

내장 RAG는 문서 적재·청크 분할·임베딩·검색을 위한 Select AI 벡터 인덱스를 생성합니다. 기존 벡터 테이블을 함수로 검색하는 예제와 구분합니다.

관리자가 대상 PDB에 디렉터리를 만들고 권한을 부여합니다. PDF는 DB 서버의 실제 경로에 두고 Oracle OS 계정이 읽을 수 있어야 합니다. 파일명은 영문·숫자 등 단일 바이트 문자로 준비합니다.

```sql
CREATE DIRECTORY DOC_DIR AS '/home/oracle/labs/data/docs/rag';
GRANT READ, WRITE ON DIRECTORY DOC_DIR TO LABADMIN;
```

MULTILINGUAL_E5_SMALL 모델을 먼저 적재하고, 실습 계정에서 다음을 확인합니다. 아래 차원 384는 해당 모델을 전제로 한 값이며 다른 모델이면 변경합니다.

```sql
SELECT model_name FROM user_mining_models
WHERE model_name = 'MULTILINGUAL_E5_SMALL';
SELECT VECTOR_DIMENSION_COUNT(
  VECTOR_EMBEDDING(MULTILINGUAL_E5_SMALL USING '검색 테스트' AS data)
) AS dimensions FROM dual;
```

임베딩 모델 준비와 파일 위치 형식은 [공식 RAG 예제](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/use-retrieval-augmented-generation-and-vectors.html)를 참고합니다. Pipeline 실행 권한과 테이블스페이스 quota는 공통 환경 구성에서 준비합니다.

### 2.1. 프로파일·Agent·벡터 인덱스 생성

```sql

-- 프로파일 생성

BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'SAIAGENT_RAG_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama",
      "model": "qwen2.5-coder:7b",
      "conversation": false,
      "temperature": 0.1,
      "max_tokens": 1024,
      "vector_index_name":"SAIAGENT_RAG_IDX",
      "embedding_model": "database:MULTILINGUAL_E5_SMALL"
    }',
    status => 'enabled'
  );
END;
/

EXEC DBMS_CLOUD_AI.SET_PROFILE('SAIAGENT_RAG_PROFILE');

-- Agent 생성
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'SAIAGENT_RAG',
    attributes => '{
      "profile_name": "SAIAGENT_RAG_PROFILE",
      "role": "You are a document retrieval assistant. Use only retrieved evidence and answer in Korean."
    }'
  );
END;
/

BEGIN

  -- 벡터 인덱스 생성
  DBMS_CLOUD_AI.CREATE_VECTOR_INDEX(
    index_name => 'SAIAGENT_RAG_IDX',
    wait_for_completion => TRUE,
    attributes        => '{
          "vector_db_provider": "oracle",
          "location": "DOC_DIR:*.pdf",
          "profile_name": "SAIAGENT_RAG_PROFILE",
          "vector_dimension": 384,
          "vector_distance_metric": "cosine",
          "pipeline_name": "SAIAGENT_RAG_PIPELINE",
          "chunk_size":700,
          "chunk_overlap":50,
          "match_limit" : 5
        }'
  );
END;
/

-- 적재 파이프라인 완료를 기다린 뒤 검색합니다.
SELECT index_name, status FROM user_cloud_vector_indexes
WHERE index_name = 'SAIAGENT_RAG_IDX';

SELECT pipeline_name, status, start_date, end_date, error_message
FROM user_cloud_pipeline_history
WHERE pipeline_name = 'SAIAGENT_RAG_PIPELINE'
ORDER BY start_date DESC;

```

### 2.2. Tool·Task·Team 생성과 실행

```sql
BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name  => 'SAIAGENT_RAG_TOOL',
    attributes => '{"tool_type": "RAG",
                      "tool_params": {"profile_name": "SAIAGENT_RAG_PROFILE"}}'
  );
END;
/

BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
      task_name =>'VSEARCH_TASK',
      attributes => '{"instruction": "반드시 RAG 도구 결과(문서 근거)만 사용해서 답변하세요. 근거가 없으면 \"제공된 문서(DOC_DIR)에서 근거를 찾지 못했습니다\"라고만 답하고, 일반 지식으로 추측하지 마세요. User question: {query}",
        "tools": ["SAIAGENT_RAG_TOOL"],
         "enable_human_tool": false
       }'
    );
END;
/

BEGIN

  -- 팀 생성
  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name  => 'RETURNAGENCY_RAG',
    attributes => '{
      "agents": [
        { "name": "SAIAGENT_RAG", "task": "VSEARCH_TASK" }
      ],
      "process": "sequential"
    }'
  );
END;
/

EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('RETURNAGENCY_RAG');

SELECT AI AGENT 제공된 문서의 주요 내용을 출처와 함께 요약해줘;
```

인덱스 생성은 기본적으로 비동기이므로 위 예제는 wait_for_completion을 TRUE로 설정했습니다. 완료 후에도 실제 문서가 검색되는지 확인합니다.

```sql
EXEC DBMS_CLOUD_AI.SET_PROFILE('SAIAGENT_RAG_PROFILE');
SELECT AI RUNSQL 문서의 주요 주제를 찾아줘;
SELECT AI NARRATE 제공된 문서의 주요 내용을 출처와 함께 요약해줘;
EXEC DBMS_CLOUD_AI.CLEAR_PROFILE;
EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
```

검색 청크와 최종 답변을 비교합니다. 문서 근거를 찾지 못하면 일반 지식으로 보충하도록 지침을 완화하기보다 적재·검색·모델 응답을 각각 점검합니다. 실행 이력은 [공통 문제 확인](./OnPremises_Setup.md#5-실행-이력과-문제-확인)을 사용합니다. 내부 PIPELINE$ 테이블명과 과거 실행 ID는 환경마다 달라 예제에 고정하지 않습니다.

## 실습 객체 정리

공유 객체가 아닌지 확인한 후 실행합니다. 원본 테이블은 삭제하지 않습니다.

```sql
BEGIN
  DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
  DBMS_CLOUD_AI_AGENT.DROP_TEAM('RETURNAGENCY', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TASK('SQL_ONLY_TASK', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TOOL('SQL', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_AGENT('SQL_TOOL_AGENT', force => TRUE);
  DBMS_CLOUD_AI.DROP_PROFILE('NL2SQL_PROFILE', force => TRUE);
  DBMS_CLOUD_AI.DROP_PROFILE('AGENT_OLLAMA_PROFILE', force => TRUE);
END;
/
```

### RAG 에이전트 정리

공유 객체가 아닌지 확인한 후 실행합니다. 원본 테이블은 삭제하지 않습니다.

```sql
BEGIN
  DBMS_CLOUD_AI.CLEAR_PROFILE;
  DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
  DBMS_CLOUD_AI_AGENT.DROP_TEAM('RETURNAGENCY_RAG', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TASK('VSEARCH_TASK', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TOOL('SAIAGENT_RAG_TOOL', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_AGENT('SAIAGENT_RAG', force => TRUE);
END;
/
```

RAG 벡터 데이터까지 제거하려는 경우에만 다음을 추가 실행합니다. 검색 원본 PDF 파일은 삭제하지 않습니다.

```sql
BEGIN
  DBMS_CLOUD_AI.DROP_VECTOR_INDEX(
    index_name => 'SAIAGENT_RAG_IDX', include_data => TRUE, force => TRUE);
  DBMS_CLOUD_AI.DROP_PROFILE('SAIAGENT_RAG_PROFILE', force => TRUE);
END;
/
```
