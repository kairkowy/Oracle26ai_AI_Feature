# Select AI Agent: HR 데이터 조회와 JOIN

> **온프레미스 기준**: Oracle AI Database 26ai의 지원 RU와 대상 PDB에서 실행합니다. 먼저 [공통 환경 구성](./OnPremises_Setup.md)에서 버전·패키지·권한·ACL·LLM 연결을 확인합니다. 엔드포인트·모델·스키마·테이블은 실제 환경에 맞게 변경합니다. 아래 SQL은 실습용이며, 생성된 객체를 정리한 후 재실행합니다.

## 사전 준비

HR의 COUNTRIES·DEPARTMENTS·EMPLOYEES·JOBS·JOB_HISTORY·LOCATIONS·REGIONS 테이블과 PK·FK가 대상 PDB에 있어야 합니다. 예제는 LABADMIN으로 실행하며 관리자가 각 테이블의 SELECT 권한을 부여합니다. HR 자체 계정으로 실행해도 프로파일의 owner는 HR입니다.

```sql
-- 관리자: 대상 PDB에서 실행
GRANT SELECT ON HR.COUNTRIES TO LABADMIN;
GRANT SELECT ON HR.DEPARTMENTS TO LABADMIN;
GRANT SELECT ON HR.EMPLOYEES TO LABADMIN;
GRANT SELECT ON HR.JOBS TO LABADMIN;
GRANT SELECT ON HR.JOB_HISTORY TO LABADMIN;
GRANT SELECT ON HR.LOCATIONS TO LABADMIN;
GRANT SELECT ON HR.REGIONS TO LABADMIN;
```

프로파일의 comments는 COMMENT, annotations는 Annotation, constraints는 PK·FK 메타데이터의 활용 설정입니다. Annotation이 JOIN을 자동으로 보장하지 않으므로 실제 생성 SQL과 결과를 확인합니다. Annotation 작성 방식은 [샘플 데이터 구성](../SelectAI_Intro_Lab/SampleDataConfig.md)을 참고합니다. 해당 문서의 SH용 스크립트를 HR에 그대로 적용하지 않습니다.

Annotation을 준비하지 않았다면 아래 annotations를 false로 바꾸고, 먼저 PK·FK와 명시적인 Task 지침을 이용해 실행합니다.

## 1. SQL Tool 생성

```sql
-- ==========================================================
-- 1.1 SQL 툴에서 사용할 데이터 프로파일 생성
-- 데이터 프로파일명 : HR_NL2SQL_PROFILE
-- 엔드포인트 : 로컬 Ollama 서비스
-- 오브젝트(HR 테이블) 리스트 추가
-- ==========================================================

BEGIN

  -- 프로파일 생성
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'HR_NL2SQL_PROFILE',
    attributes   => q'!
{
  "provider_endpoint": "http://service-ollama",
  "model": "gemma3:12b",
  "conversation": true,
  "max_tokens": 1024,
  "temperature": 0.0,
  "comments": false,
  "annotations": true,
  "constraints": true,
  "enforce_object_list": true,
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

-- comments와 annotations는 서로 다른 메타데이터 설정입니다.

-- ==========================================================
-- 1.2 Tool (SQL) 생성
-- Tool Name : HR_SQL
-- ==========================================================

-- HR SQL 도구 생성
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

## 2. Task 생성

```sql
-- ==================================================
-- Task 생성
-- Task Name : HR_SQL_TASK
-- ===================================================

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
      '- If the tool returns an error, briefly report the error in Korean. User question: {query}',

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

## 3. AI Agent 생성

```sql
-- ================================================
-- Agent Name : HR_SQL_AGENT
-- ================================================

BEGIN
  -- Agent에서 사용할 새 프로파일 기반 Agent 생성
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

## 4. Agent Team 생성

```sql
-- ======================================================
-- Agent team 생성
-- Agent Name : HR_SQL_AGENCY
-- ======================================================

BEGIN

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

## 5. 실행과 결과 검증

```sql
EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('HR_SQL_AGENCY');
SELECT DBMS_CLOUD_AI_AGENT.GET_TEAM() AS current_team FROM dual;
SELECT AI AGENT 유럽(Europe) 지역 직원의 직무별 평균 급여와 직원 수를 알려줘;
EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
```

같은 질문의 원본 SQL 결과와 도구 이력을 비교합니다. 대화 ID를 재사용하는 RUN_TEAM 예제와 전체 CLOB 출력은 [공통 실행 안내](./OnPremises_Setup.md#4-실행과-대화-문맥)를 참고합니다.

다음 SQL과 비교해 직무별 그룹화, 유럽 지역 필터, 급여 단위를 확인합니다. HR의 SALARY 값을 임의의 원화나 연봉으로 환산하지 않습니다.

```sql
SELECT j.job_title, COUNT(*) AS employee_count,
       ROUND(AVG(e.salary), 2) AS avg_salary
FROM HR.EMPLOYEES e
JOIN HR.JOBS j ON j.job_id = e.job_id
JOIN HR.DEPARTMENTS d ON d.department_id = e.department_id
JOIN HR.LOCATIONS l ON l.location_id = d.location_id
JOIN HR.COUNTRIES c ON c.country_id = l.country_id
JOIN HR.REGIONS r ON r.region_id = c.region_id
WHERE r.region_name = 'Europe'
GROUP BY j.job_title
ORDER BY j.job_title;
```

실제 도구 호출과 입력·출력은 [공통 모니터링](./OnPremises_Setup.md#5-실행-이력과-문제-확인)에서 tool_name = 'HR_SQL'로 확인합니다.

참고: [Oracle Agent 공식 예제](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/examples-using-select-ai-agent1.html), [메타데이터와 Annotation](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/data-and-metadata-concepts.html).

## 실습 객체 정리

공유 객체가 아닌지 확인한 후 실행합니다. 원본 테이블은 삭제하지 않습니다.

```sql
BEGIN
  DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
  DBMS_CLOUD_AI_AGENT.DROP_TEAM('HR_SQL_AGENCY', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TASK('HR_SQL_TASK', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_TOOL('HR_SQL', force => TRUE);
  DBMS_CLOUD_AI_AGENT.DROP_AGENT('HR_SQL_AGENT', force => TRUE);
  DBMS_CLOUD_AI.DROP_PROFILE('HR_NL2SQL_PROFILE', force => TRUE);
END;
/
```
