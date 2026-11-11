# Select AI Agent: 통계 분석 실습

> **온프레미스 기준**: Oracle AI Database 26ai의 지원 RU와 대상 PDB에서 실행합니다. 먼저 [공통 환경 구성](./OnPremises_Setup.md)에서 버전·패키지·권한·ACL·LLM 연결을 확인합니다. 엔드포인트·모델·스키마·테이블은 실제 환경에 맞게 변경합니다. 아래 SQL은 실습용이며, 생성된 객체를 정리한 후 재실행합니다.

## 사전 준비와 데이터 확인

LABADMIN의 TOUR_HIST_TBL(제주 관광객 카드 이용 이력)을 사용합니다. 원본 데이터와 DDL은 이 문서에 포함되지 않습니다. 다음 조회로 실제 컬럼·데이터형·건수를 확인하고, 업종과 결제 금액 컬럼이 어떤 이름인지 기록합니다. 데이터가 준비되지 않았다면 먼저 적재하거나 자신의 테이블로 아래 object_list와 질문을 변경합니다.

```sql
SELECT column_name, data_type FROM all_tab_columns
WHERE owner = 'LABADMIN' AND table_name = 'TOUR_HIST_TBL'
ORDER BY column_id;
SELECT COUNT(*) AS row_count FROM LABADMIN.TOUR_HIST_TBL;
```

금액의 단위, 취소 거래 포함 여부, NULL 처리와 집계 기준은 원본 데이터 정의를 확인합니다. LLM이 컬럼 이름이나 단위를 추정하도록 두지 않습니다.

아래는 프로파일·Tool·Task·Agent·Team 순으로 구성합니다. Agent를 먼저 생성하는 공식 시작 예제와 순서는 다르지만, 각 객체를 참조하기 전에 생성하도록 배치했습니다.

## 1. 프로파일과 SQL 도구 생성

```sql

-- ==========================================================
-- Step 1-1. Tool에서 사용할 데이터 프로파일 생성
-- 프로파일명 : ANALYSIS_PROFILE
-- 설명 : Ollama 연결·모델·대상 객체·응답 옵션을 지정합니다.
-- ==========================================================

-- 프로파일 생성
BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'ANALYSIS_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama",
      "model": "gemma2:9b",
      "enforce_object_list": true,
      "object_list": [
                      {"owner": "LABADMIN", "name": "TOUR_HIST_TBL"}
                     ],
      "max_tokens": 4096,
      "temperature": 0.1,
     "conversation": false
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

## 2. Task 생성

```sql
-- =================================================================================
-- 2. Task 생성
-- Task name : ANALYSIS_TASK
-- 설명 : 작업은 도구 선택(어떤 도구를 사용할지), 매개변수 매핑(어떤 파라미터를 전달할지) 및
-- 실행 정책을 안내하며, 하위 단계에서 읽고 요약할 수 있는 결과를 생성한다
-- =================================================================================

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
    'tools' VALUE JSON_ARRAY('SQL_ANALYSIS_TOOL'),
    'enable_human_tool' VALUE false
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name  => 'ANALYSIS_TASK',
    attributes => v_attributes
  );
END;
/
```

## 3. Agent 생성

```sql
-- ================================================================
-- 3. Agent 생성
-- Agent name : ANALYTIC_BOT
-- ================================================================

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

## 4. Agent 팀 생성

```sql
-- ===============================================
-- Step 4.1 : Team 생성
-- 설명: 에이전트와 Task를 연결하여 팀 구성
-- Team Name : ANALYTIC_TEAM
-- ===============================================

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

```

## 5. 실행과 통계 검증

```sql
EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('ANALYTIC_TEAM');
SELECT DBMS_CLOUD_AI_AGENT.GET_TEAM() AS current_team FROM dual;
SELECT AI AGENT 업종별 카드 결제 금액의 합계와 원본 행 수를 계산하고 합계가 큰 순서로 보여줘;
EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
```

같은 질문의 원본 SQL 결과와 도구 이력을 비교합니다. 대화 ID를 재사용하는 RUN_TEAM 예제와 전체 CLOB 출력은 [공통 실행 안내](./OnPremises_Setup.md#4-실행과-대화-문맥)를 참고합니다.

예제 데이터의 컬럼명이 환경마다 다를 수 있으므로 비교 SQL은 컬럼 확인 후 작성합니다. 다음은 템플릿이며 꺾쇠괄호 안을 실제 식별자로 바꾼 뒤 실행합니다. 한글·공백이 있는 컬럼명은 큰따옴표를 사용합니다.

```sql
SELECT <업종_컬럼> AS industry,
       COUNT(*) AS row_count,
       SUM(<결제금액_컬럼>) AS total_amount
FROM LABADMIN.TOUR_HIST_TBL
GROUP BY <업종_컬럼>
ORDER BY total_amount DESC NULLS LAST;
```

COUNT(*)는 원본 행 수입니다. 데이터가 이미 집계된 이력이라면 카드 이용 건수는 별도 건수 컬럼의 SUM일 수 있습니다. 질문에서 행 수와 거래 건수를 구분하고, 에이전트가 생성한 SQL의 집계 방식도 확인합니다.

생성 SQL·도구 결과·최종 응답의 숫자를 대조합니다. 실행 이력은 [공통 모니터링](./OnPremises_Setup.md#5-실행-이력과-문제-확인)에서 tool_name = 'SQL_ANALYSIS_TOOL'로 확인합니다.

참고: [Oracle Agent 생성·실행 예제](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/examples-using-select-ai-agent1.html), [Agent 조회 뷰](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/dbms_cloud_ai_agent-views.html).

## 실습 객체 정리

공유 객체가 아닌지 확인한 후 실행합니다. 원본 테이블은 삭제하지 않습니다.

```sql
BEGIN
  DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
  DBMS_CLOUD_AI_AGENT.DROP_TEAM('ANALYTIC_TEAM', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TASK('ANALYSIS_TASK', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TOOL('SQL_ANALYSIS_TOOL', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_AGENT('ANALYTIC_BOT', force => TRUE);
  DBMS_CLOUD_AI.DROP_PROFILE('ANALYSIS_PROFILE', force => TRUE);
END;
/
```
