### Oracle26ai SelectAI Agent 

Select AI Agent는 PL/SQL 툴을 사용하여 작업의 자동화를 구축하고, 자연어 상호 작용을 통해 데이터에 대한 대화형 액세스를 활성화하고, 외부 서비스를 연결하는 데 사용할 수 있음.

#### SelectAI Agent 생성 및 실행 순서

  1.AI Agent 생성 - 2.Tool 생성 - 3.Task 생성 - 4.Team 생성 - 5.실행

  지원 Tools : SQL, RAG, WEBSEARCH, NOTIFICATION(EMAIL,SLACK)


#### 1. SQL 툴 사용 케이스

```sql
GRANT EXECUTE on DBMS_CLOUD_AI_AGENT to labadmin;

```

1. AI Agent 생성

```sql

-- Agent에서 사용할 프로파일 정리 및 생성

BEGIN
  BEGIN
  -- 있으면 삭제 (force => true)
  DBMS_CLOUD_AI.DROP_PROFILE(
    profile_name => 'AGENT_OLLAMA_PROFILE',
    force        => TRUE
  );
  END;

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

-- Agent 정리 및 생성
BEGIN
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_AGENT('SQL_TOOL_AGENT', force => TRUE); 
        EXCEPTION WHEN OTHERS THEN NULL; 
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'SQL_TOOL_AGENT',
    attributes => '{
      "profile_name": "AGENT_OLLAMA_PROFILE",
      "role": "You are an experienced customer agent who deals with customers return request."
    }'
  );
END;
/
```

2. Tool 생성

- 지원 되는 툴 : SQL, RAG, WEBSEARCH, NOTIFICATION(EMAIL,SLACK)

```sql

-- SQL tool을 위한 프로타일 생성(테이블 리스트)

BEGIN
  -- 기존 프로파일 있으면 삭제 (없어도 무시)
  BEGIN
    DBMS_CLOUD_AI.DROP_PROFILE(
      profile_name => 'NL2SQL_PROFILE',
      force        => TRUE
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL; 
  END;

  -- 프로파일 생성
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'NL2SQL_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama",
      "model": "qwen2.5-coder:7b",
      "conversation": false,
      "object_list": [
        {"owner": "LABADMIN", "name": "TOUR_HIST_TBL_ENG"},
        {"owner": "LABADMIN", "name": "DOC_STORE"}
      ]    
    }');
END;
/

-- TOUR_HIST_TBL
-- TOUR_HIST_TBL_ENG
-- SQL 툴 생성

BEGIN
  -- 있으면 제거(없으면 에러날 수 있으니 예외 무시)
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_TOOL('SQL'); EXCEPTION WHEN OTHERS THEN NULL; END;

  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name  => 'SQL',
    attributes => '{"tool_type": "SQL","tool_params": { "profile_name": "NL2SQL_PROFILE" }
    }'
  );
END;
/

```

3. Task 생성

```sql
BEGIN
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_TASK('SQL_ONLY_TASK', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name  => 'SQL_ONLY_TASK',
    attributes => '{
      "tools": ["SQL"],
      "instruction": "사용자 질문에 대해 DB의 TOUR_HIST_TBL_ENG 테이블을 SQL로 조회해서 답하세요. User question: {query}.",
      "enable_human_tool": true
    }'
  );
END;
/
```

4. Team 생성

```sql

BEGIN
  -- 팀 제거
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_TEAM('RETURNAGENCY', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

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

5. AI Agent 실행

```sql

-- 세션에 팀 지정 후, 자연어로 실행
EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;

EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('RETURNAGENCY');

-- 지금 세션에 어떤 팀이 설정됐는지 확인
SELECT DBMS_CLOUD_AI_AGENT.GET_TEAM() AS current_team FROM dual;
CURRENT_TEAM
----------------------------------------------------
"LABADMIN"."RETURNAGENCY"


select ai agent tour_hist_tbl_eng 테이블의 컬럼명 출력해줘;

RESPONSE
----------------------------------------------------------
The column names of the `TOUR_HIST_TBL_ENG` table are:
- EXE_MONTH
- TOUR_TYPE
- CLASS_A
- CLASS_B
- TERRITORY_NAME
- GENDER
- CLASS_AGE
- CARD_TR_AMOUNT
- CARD_TR_CNT
- CARD_PER_AMOUNT

select ai agent '건당이용금액 중에서 제일 많은 금액 순으로 5개 출력해줘.';

RESPONSE
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
The top 5 most expensive tours based on the total amount paid per person are:

1. EXE_MONTH: 16-Aug, TOUR_TYPE: 내국인 관광객, CLASS_A: 제주시, CLASS_B: 용담2동, TERRITORY_NAME: 기념품 점, GENDER: 여, CLASS_AGE: 20대, CARD_TR_AMOUNT: 64277700, CARD_TR_CNT: 2543, CARD_PER_AMOUNT:
 25276
2. EXE_MONTH: 15-Aug, TOUR_TYPE: 내국인 관광객, CLASS_A: 제주시, CLASS_B: 용담2동, TERRITORY_NAME: 기념품 점, GENDER: 여, CLASS_AGE: 30대, CARD_TR_AMOUNT: 63835780, CARD_TR_CNT: 2357, CARD_PER_AMOUNT:
 27083
3. EXE_MONTH: 16-Jul, TOUR_TYPE: 내국인 관광객, CLASS_A: 제주시, CLASS_B: 용담2동, TERRITORY_NAME: 기념품 점, GENDER: 여, CLASS_AGE: 20대, CARD_TR_AMOUNT: 61323000, CARD_TR_CNT: 2574, CARD_PER_AMOUNT:
 23824
4. EXE_MONTH: 15-Apr, TOUR_TYPE: 내국인 관광객, CLASS_A: 제주시, CLASS_B: 용담2동, TERRITORY_NAME: 농축수산품, GENDER: 남, CLASS_AGE: 50대, CARD_TR_AMOUNT: 59866370, CARD_TR_CNT: 694, CARD_PER_AMOUNT:
 86263
5. EXE_MONTH: 14-Nov, TOUR_TYPE: 내국인 관광객, CLASS_A: 제주시, CLASS_B: 용담2동, TERRITORY_NAME: 농축수산품, GENDER: 남, CLASS_AGE: 50대, CARD_TR_AMOUNT: 59840560, CARD_TR_CNT: 715, CARD_PER_AMOUNT:
 83693

select ai agent '카드 이용금액을 남, 여로 구분해서 합계를 내주세요';

RESPONSE
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
남성의 카드 이용금액 합계는 2,571,491,0191이고, 여성의 카드 이용금액 합계는 2,288,827,1083입니다.


select ai agent '카드 이용금액을 나이대별로 통계를 내주세요';
RESPONSE
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
The total card utilization amount by age group is as follows:

- 30대: 14,856,286,866
- 40대: 14,370,117,286
- 50대: 11,976,816,069
- 20대: 7,399,961,053
```



#### 2. RAG 툴 사용 케이스


```sql

-- 프로파일 생성

BEGIN
  BEGIN
    DBMS_CLOUD_AI.DROP_PROFILE('SAIAGENT_RAG_PROFILE', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

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


-- Agent 정리 및 생성
BEGIN
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_AGENT('SAIAGENT_RAG', force => TRUE); 
        EXCEPTION WHEN OTHERS THEN NULL; 
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'SAIAGENT_RAG',
    attributes => '{
      "profile_name": "SAIAGENT_RAG_PROFILE",
      "role": "You are an experienced customer agent who deals with customers return request."
    }'
  );
END;
/


BEGIN
  -- 기존 인덱스 있으면 삭제
  BEGIN
    DBMS_CLOUD_AI.DROP_VECTOR_INDEX(
      index_name   => 'SAIAGENT_RAG_IDX',
      include_data => TRUE,
      force        => TRUE
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  -- 벡터 인덱스 생성
  DBMS_CLOUD_AI.CREATE_VECTOR_INDEX(
    index_name => 'SAIAGENT_RAG_IDX',
    attributes        => '{
          "vector_db_provider": "oracle",
          "location": "DOC_DIR:*.pdf",
          "profile_name": "SAIAGENT_RAG_PROFILE",
          "vector_dimension": 384,
          "vector_distance_metric": "cosine",
          "chunk_size":700,
          "chunk_overlap":50,
          "match_limit" : 5
        }'
  );
END;
/

select * from tab where tname like 'VECTOR$SAIAGENT_RAG_IDX%' or tname like 'PIPELINE%';

TNAME                                                                            TABTYPE               CLUSTERID
-------------------------------------------------------------------------------- -------------------- ----------
VECTOR$SAIAGENT_RAG_IDX$74699_74706_0$IVF_FLAT_CENTROIDS                         TABLE
VECTOR$SAIAGENT_RAG_IDX$74699_74706_0$IVF_FLAT_CENTROID_PARTITIONS               TABLE
PIPELINE$6$64_STATUS                                                             TABLE
PIPELINE$15$92_STATUS                                                             TABLE

select name, status, error_message from PIPELINE$15$92_STATUS;

NAME                           STATUS                         ERROR_MESSAGE
------------------------------ ------------------------------ ------------------------------
SPRi_AI_202404.pdf             COMPLETED
software_order.pdf             COMPLETED

EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;

BEGIN
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_TOOL('SAIAGENT_RAG_TOOL'); 
    EXCEPTION WHEN OTHERS THEN NULL; 
  END;

  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name  => 'SAIAGENT_RAG_TOOL',
    attributes => '{"tool_type": "RAG",
                      "tool_params": {"profile_name": "SAIAGENT_RAG_PROFILE"}}'
  );
END;
/


BEGIN
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_TASK('VSEARCH_TASK', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

    DBMS_CLOUD_AI_AGENT.CREATE_TASK(
      task_name =>'VSEARCH_TASK',
      attributes => '{"instruction": "반드시 RAG 도구 결과(문서 근거)만 사용해서 답변하세요. 근거가 없으면 \"제공된 문서(DOC_DIR)에서 근거를 찾지 못했습니다\"라고만 답하고, 일반 지식으로 추측하지 마세요. User question: {query}",
        "tools": ["SAIAGENT_RAG_TOOL"],
         "enable_human_tool" : "false"
       }'
    );
END;
/

-- 1. instruction에 명확한 가이드 중요
-- 2. enable_human_tool 옵션에서 사람 개입없다면 false 값 권고

BEGIN
  -- 팀 제거
  BEGIN DBMS_CLOUD_AI_AGENT.DROP_TEAM('RETURNAGENCY_RAG', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

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


SELECT AI AGENT 공공기관 소프트웨어 분리발주 대상사업에는 어떤 것들이 있나요?;

RESPONSE
--------------------------------------------------------------------------------
공공기관이 소프트웨어를 분리발주하는 경우에 대한 세부적인 대상 및 방법 등은 정의
되어 있습니다. 분리발주 대상 사업은 총 사업 규모가 5억원 이상인 소프트웨어 사업
을 분리발주 대상 사업으로 합니다.
```


문제 추적

```sql

-- 모델 응답 확인 방법

EXEC DBMS_CLOUD_AI.SET_PROFILE('SAIAGENT_RAG_PROFILE');

SELECT AI CHAT 'ping';

RESPONSE
---------------
Pong!


-- 최근 팀 실행 상태 확인

select TEAM_EXEC_ID, TEAM_NAME, STATE from user_ai_agent_team_history
where TEAM_NAME = 'RETURNAGENCY_RAG' and state = 'RUNNING';

TEAM_EXEC_ID                                       TEAM_NAME                      STATE
-------------------------------------------------- ------------------------------ --------------------
4B366B0F-D95F-2681-E063-187B000ABF32               RETURNAGENCY_RAG               RUNNING


-- 특정 team_exec_id에 대해 task/tool 레벨도 확인

SELECT TEAM_EXEC_ID, TEAM_NAME, STATE
FROM   user_ai_agent_task_history
WHERE  team_exec_id = '4B366B0F-D982-2681-E063-187B000ABF32'
ORDER  BY start_date DESC;

TEAM_EXEC_ID                                       TEAM_NAME                      STATE
-------------------------------------------------- ------------------------------ --------------------
4B366B0F-D95F-2681-E063-187B000ABF32               RETURNAGENCY_RAG               RUNNING


SELECT INVOCATION_ID, TEAM_EXEC_ID, AGENT_NAME, TOOL_NAME, TASK_NAME, OUTPUT
FROM   user_ai_agent_tool_history
WHERE  team_exec_id = '4B3822DE-5E64-4505-E063-187B000AD895'
ORDER  BY start_date DESC;

INVOCATION_ID TEAM_EXEC_ID                                       AGENT_NAME                     TOOL_NAME            TASK_NAME                      OUTPUT
------------- -------------------------------------------------- ------------------------------ -------------------- ------------------------------ --------------------------------------------------------------------------------
           64 4B366B0F-D956-2681-E063-187B000ABF32               SAIAGENT_RAG                   SAIAGENT_RAG_TOOL    VSEARCH_TASK                   {"status": "success", "result": "{"status": "error", "message": "Error from RA
                                                                                                                                                    G

-- 에러 메시지 상세 확인

SELECT dbms_lob.substr(output, 4000, 1) AS out_1
FROM   user_ai_agent_tool_history
WHERE  invocation_id = 71;

OUT_1
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
{"status": "success", "result": "{"status": "error", "message": "Error from RAG search tool: ORA-20000: Sorry, unfortunately the response for your natural language prompt was not generated using the sources of your data. Here is some more information to help you further:

분리발주는 공공기관이 소프트웨어를 분리하여 발주하는 제도입니다. 이는 일괄발주와 달리 SW구매만을 별도로 분리하여 발주하고, 평가·선정, 계약, 사업관리 등을 실시하는 것을 의미합니다.

1. **분리발주 대상 사업**: 총 사업 규모가 5억원 이상인"}"}


-- 파이프라인이 실제로 문서를 인제스트했는지

SELECT pipeline_name, status, start_date, end_date, error_message
FROM   user_cloud_pipeline_history
ORDER  BY start_date DESC
FETCH FIRST 20 ROWS ONLY;

SELECT COUNT(*) FROM PIPELINE$12$87_STATUS;


```
