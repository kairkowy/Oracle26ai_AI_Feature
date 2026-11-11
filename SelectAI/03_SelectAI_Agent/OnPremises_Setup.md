# 온프레미스 Select AI Agent 실습 환경

이 문서는 **고객이 직접 관리하는 Oracle AI Database 26ai의 PDB**에서 이 폴더의 예제를 실행하기 위한 공통 준비와 점검 절차입니다. 확인 기준일은 2026-11-11입니다. 예제의 Ollama 모델과 데이터는 실습용 구성이고, Oracle 공식 문서의 필수 모델이나 공식 성능 검증 결과를 의미하지 않습니다.

## 1. 지원 버전과 환경 구분

먼저 [Oracle Select AI 기능 지원표](https://docs.oracle.com/en/database/oracle/oracle-database/26/saicm/index.html)의 **Oracle AI Database 23.26.1** 열을 확인합니다. 이 열에서 AI Agent, SQL·RAG·WEBSEARCH·NOTIFICATION 도구와 사용자 정의 PL/SQL 도구가 지원됩니다. 같은 표의 **23.7+** 열은 AI Agent와 내장 RAG가 지원되지 않습니다. 따라서 제품명이 26ai라는 사실이나 NL2SQL 실행 성공만으로 Agent 지원을 판단하지 않습니다. 다른 RU는 해당 RU의 문서와 지원표를 함께 확인합니다.

온프레미스에서는 DBMS_CLOUD 계열 패키지를 직접 설치·구성합니다. Autonomous의 사전 설치, DWROLE, 관리형 테이블스페이스, OCI 리소스 프린시펄 설정을 그대로 전제하지 않습니다. 로컬 LLM과 로컬 파일만 사용하는 예제에서 OCI 계정이나 Object Storage는 공통 필수 조건이 아닙니다. 외부 AI 제공자나 클라우드 저장소를 선택하면 해당 서비스의 인증과 네트워크 구성이 추가됩니다.

SQL*Plus 또는 SQLcl에서 실습 PDB 서비스로 접속합니다.

```sql
SELECT banner_full FROM v$version;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS pdb_name,
       SYS_CONTEXT('USERENV', 'CURRENT_USER') AS current_user
FROM dual;
```

관리자는 설치·패치 상태를 함께 확인합니다. 아래 DBA 뷰는 실습 계정에서 실행하지 않습니다.

```sql
SELECT patch_id, action, status, action_time, description
FROM dba_registry_sqlpatch
ORDER BY action_time DESC;

SELECT owner, object_name, object_type, status
FROM dba_objects
WHERE owner = 'C##CLOUD$SERVICE'
  AND object_name IN ('DBMS_CLOUD', 'DBMS_CLOUD_AI', 'DBMS_CLOUD_AI_AGENT',
                      'DBMS_CLOUD_PIPELINE')
  AND object_type IN ('PACKAGE', 'PACKAGE BODY')
ORDER BY object_name, object_type;
```

설치된 API 인수도 확인합니다. 예를 들어 내장 RAG 예제는 `CREATE_VECTOR_INDEX`의 `WAIT_FOR_COMPLETION` 인수를 사용합니다. 지원 RU인데도 인수가 없으면 Oracle Home과 DBMS_CLOUD 설치·패치 적용 상태를 먼저 확인합니다.

```sql
SELECT package_name, object_name, argument_name, data_type, in_out
FROM dba_arguments
WHERE owner = 'C##CLOUD$SERVICE'
  AND ((package_name = 'DBMS_CLOUD_AI_AGENT' AND object_name = 'RUN_TEAM')
    OR (package_name = 'DBMS_CLOUD_AI' AND object_name = 'CREATE_VECTOR_INDEX'))
ORDER BY package_name, object_name, overload, sequence;
```

## 2. 패키지 설치와 계정 권한

관리자는 [기존 환경 구성 안내](../01_SelectAI_Intro_Lab/SelectAiConfigure.md)를 참고해 설치·Wallet·ACL을 준비합니다. 설치 근거는 [Oracle DBMS_CLOUD 설치 문서](https://docs.oracle.com/en/database/oracle/oracle-database/26/sutil/installing-dbms_cloud.html)입니다. Oracle Home의 `catclouduser.sql`과 `dbms_cloud_install.sql`을 `catcon.pl`로 실행하고, 설치 로그와 대상 PDB의 패키지 상태를 확인합니다. 새 DBMS_CLOUD 배포가 포함된 RU 적용 후에는 공식 절차에 따라 설치 스크립트를 다시 실행합니다.

다음은 이미 생성된 실습 계정 `LABADMIN`의 예입니다. 관리자가 **대상 PDB**에서 실행하며, 계정명과 테이블스페이스는 실제 환경에 맞게 변경합니다.

```sql
GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE TO LABADMIN;
GRANT EXECUTE ON DBMS_CLOUD TO LABADMIN;
GRANT EXECUTE ON DBMS_CLOUD_AI TO LABADMIN;
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO LABADMIN;
ALTER USER LABADMIN QUOTA 100M ON USERS;

-- 내장 RAG의 벡터화 파이프라인을 사용하는 경우 추가
GRANT EXECUTE ON DBMS_CLOUD_PIPELINE TO LABADMIN;
GRANT CREATE JOB TO LABADMIN;

-- 실습 계정이 ONNX 임베딩 모델을 직접 적재하는 경우 추가
GRANT CREATE MINING MODEL TO LABADMIN;
```

조회할 타 스키마 테이블의 SELECT 권한은 별도로 부여합니다. 저장 함수에서 타 스키마 객체를 참조하면 함수 소유자에게 필요한 객체 권한을 직접 부여합니다. 프로파일의 `object_list`는 데이터베이스 권한을 부여하는 설정이 아닙니다.

참고: [Agent 사용 전제 조건](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/prerequisites-using-select-ai-agent.html), [DBMS_CLOUD 계열 구성](https://docs.oracle.com/en/database/oracle/oracle-database/26/sutil/dbms_cloud-family-packages.html).

## 3. LLM 연결·ACL·Wallet

이 폴더는 `http://service-ollama`를 OpenAI 호환 **기본 URL**의 예시로 사용합니다. 데이터베이스가 접속하는 주소이므로 DB 서버에서 이름 해석과 해당 포트 접근이 가능해야 합니다. Nginx와 80번 포트는 실습 구성의 선택 사항입니다.

이 폴더의 프로파일은 Oracle의 OpenAI 호환 제공자 안내에 따라 `provider_endpoint`와 `model`을 지정하고, `provider`는 함께 지정하지 않습니다. 기본 URL에 `/v1/chat/completions`를 붙이지 않습니다. 기존 프록시가 URL을 재작성한다면 실제 전달 경로도 확인합니다. 기존 환경 구성 문서의 /v1 주소 예시보다 이 폴더의 기본 URL 설정을 우선 적용하고, 사용 RU의 호출 경로를 확인합니다. 이 원칙은 [제공자 선택](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/select-your-ai-provider-and-ai-models.html)과 [AI 프로파일](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/manage-ai-profiles.html)에 근거합니다.

관리자는 [기존 ACL·Wallet 설정](../01_SelectAI_Intro_Lab/SelectAiConfigure.md)에 따라 DBMS_CLOUD 서비스 계정과 실습 계정의 접근 경로를 구성합니다. ACL의 호스트에는 프로토콜과 경로를 넣지 않습니다. HTTPS는 인증서 체인을 신뢰하는 Wallet과 `SSL_WALLET` 데이터베이스 속성을 확인합니다. HTTP에서도 사용 RU의 DBMS_CLOUD 구성에 필요한 Wallet 설정을 점검합니다.

인증 없는 내부 Ollama를 전제로 한 예제에는 `credential_name`을 넣지 않았습니다. 인증을 적용한 엔드포인트는 `DBMS_CLOUD.CREATE_CREDENTIAL`로 자격 증명을 등록하고 프로파일에서 참조합니다. 패키지 설정, 호스트 ACL, Wallet, 제공자 인증은 각각 확인합니다.

도구·팀을 연결하기 전에 별도의 점검용 프로파일로 LLM 연결을 확인합니다. 이미 같은 이름의 프로파일이 있다면 다른 이름을 사용합니다. 아래 모델명은 실제 설치한 모델로 변경합니다.

```sql
BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'AGENT_CONNECT_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama",
      "model": "qwen2.5-coder:7b",
      "conversation": false
    }'
  );
END;
/
EXEC DBMS_CLOUD_AI.SET_PROFILE('AGENT_CONNECT_PROFILE');
SELECT AI CHAT 한국어로 짧은 인사 한 문장을 작성해줘;
EXEC DBMS_CLOUD_AI.CLEAR_PROFILE;
EXEC DBMS_CLOUD_AI.DROP_PROFILE('AGENT_CONNECT_PROFILE', force => TRUE);
```

사용할 모델은 SQL 생성뿐 아니라 Agent의 도구 선택과 입력값 생성을 처리할 수 있어야 합니다. 한국어 지원 여부만으로 도구 호출의 정확성을 보장할 수는 없습니다. 영어 지침은 이 예제의 작성 방식이며 Oracle API의 언어 제한이 아닙니다.

ONNX 모델 적재는 [Oracle 공식 임베딩 모델 적재 예제](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/import-onnx-models-oracle-ai-database-end-end-example.html)를 참고합니다. 임베딩 용도로 변환한 ONNX 파일과 필요한 토크나이저·메타데이터를 준비하고, 대상 스키마에서 적재한 뒤 VECTOR_EMBEDDING 호출을 먼저 확인합니다.

## 4. 실행과 대화 문맥

객체 구성은 **프로파일 → Agent → Tool → Task → Team → 실행** 순서로 읽으면 됩니다. 사용자 정의 함수는 Tool보다 먼저 준비합니다. 이 폴더의 개별 예제는 객체 간 참조가 충족되도록 순서를 배치했습니다. [공식 시작 절차](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/getting-started-select-ai-agent.html)

SQL*Plus·SQLcl의 같은 세션에서는 `SET_TEAM` 후 `SELECT AI AGENT`를 사용합니다. 연결 풀처럼 세션이 바뀌는 애플리케이션은 `RUN_TEAM`의 `team_name`을 명시합니다. `CLEAR_TEAM`은 세션 설정을 해제하며 실행 취소나 팀 객체 삭제를 의미하지 않습니다.

다음은 대화 ID를 재사용하는 두 번의 호출 예입니다. SQL*Plus·SQLcl 바인드 변수로 대화 ID를 보관하므로 별도 전역 패키지는 필요 없습니다. 실행할 팀은 미리 생성하고, 프로파일의 대화 설정도 확인합니다.

```sql
SET SERVEROUTPUT ON
VARIABLE agent_conversation_id VARCHAR2(128)

BEGIN
  :agent_conversation_id := DBMS_CLOUD_AI.CREATE_CONVERSATION();
END;
/

DECLARE
  l_response CLOB;
  PROCEDURE print_clob(p_text CLOB) IS
    l_pos PLS_INTEGER := 1;
    l_piece VARCHAR2(32767);
  BEGIN
    WHILE l_pos <= NVL(DBMS_LOB.GETLENGTH(p_text), 0) LOOP
      l_piece := DBMS_LOB.SUBSTR(p_text, 4000, l_pos);
      DBMS_OUTPUT.PUT_LINE(l_piece);
      l_pos := l_pos + LENGTH(l_piece);
    END LOOP;
  END;
BEGIN
  l_response := DBMS_CLOUD_AI_AGENT.RUN_TEAM(
    team_name   => 'HR_SQL_AGENCY',
    user_prompt => '유럽 지역 직원의 직무별 평균 급여를 알려줘.',
    params      => JSON_OBJECT('conversation_id' VALUE :agent_conversation_id)
  );
  print_clob(l_response);

  l_response := DBMS_CLOUD_AI_AGENT.RUN_TEAM(
    team_name   => 'HR_SQL_AGENCY',
    user_prompt => '같은 조건으로 직무별 직원 수도 함께 알려줘.',
    params      => JSON_OBJECT('conversation_id' VALUE :agent_conversation_id)
  );
  print_clob(l_response);
END;
/
```

`conversation_id`와 실행 이력의 `team_exec_id`는 서로 다른 식별자입니다. 사용자에게 추가 질문을 하도록 구성한 작업은 `WAITING_FOR_HUMAN` 상태에서 같은 대화 ID로 후속 입력을 전달합니다. 이 폴더의 자동 조회 예제는 Task의 `enable_human_tool`을 JSON boolean `false`로 지정합니다. 이 값은 추가 질문 기능의 설정이고, SQL 권한이나 트랜잭션 승인 장치는 아닙니다. [공식 실행 예제](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/examples-using-select-ai-agent1.html)

## 5. 실행 이력과 문제 확인

사용자 소유 객체는 USER 뷰로 확인합니다. DB 전체를 보는 DBA 뷰는 관리자가 사용합니다. 먼저 실제 RU의 뷰 컬럼을 확인한 뒤 필요한 컬럼만 조회합니다.

```sql
DESC USER_AI_AGENT_TEAM_HISTORY
DESC USER_AI_AGENT_TASK_HISTORY
DESC USER_AI_AGENT_TOOL_HISTORY

SELECT team_exec_id, team_name, state, start_date, end_date
FROM user_ai_agent_team_history
ORDER BY start_date DESC
FETCH FIRST 10 ROWS ONLY;

SELECT team_exec_id, task_name, agent_name, start_date, end_date
FROM user_ai_agent_task_history
ORDER BY start_date DESC
FETCH FIRST 10 ROWS ONLY;

SELECT team_exec_id, tool_name, task_name, agent_name,
       DBMS_LOB.SUBSTR(input, 1000, 1) AS input_preview,
       DBMS_LOB.SUBSTR(output, 1000, 1) AS output_preview,
       start_date, end_date
FROM user_ai_agent_tool_history
ORDER BY start_date DESC
FETCH FIRST 10 ROWS ONLY;
```

같은 실행의 상세 내역은 조회한 `team_exec_id`로 Task와 Tool 이력을 필터링합니다. 입력·출력 CLOB은 필요에 따라 나머지 구간도 조회합니다. CLOB의 `LENGTH`와 `DBMS_LOB.GETLENGTH`는 문자 길이이며 바이트 수가 아닙니다. [공식 Agent 뷰](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/dbms_cloud_ai_agent-views.html)

| 증상 | 확인할 내용 |
| --- | --- |
| 패키지·뷰를 찾지 못함 | RU 지원 범위, PDB 접속 대상, 패키지 설치와 실행 권한 |
| LLM 호출 실패 | DB 서버의 DNS·포트, ACL, SSL_WALLET·인증서, 인증 정보, 기본 URL과 프록시 경로 |
| CHAT은 되지만 Agent가 도구를 사용하지 않음 | Task의 tools, Agent의 profile_name, 모델의 도구 호출 결과와 실행 이력 |
| 조회 결과가 질문과 다름 | 원본 질문, 생성 SQL, 실제 SQL 결과, 그룹 기준과 단위 |
| RAG 결과가 없거나 출처 검증 실패 | 문서 추출·벡터화 완료, 임베딩 모델 일치, 검색된 청크와 답변의 근거 일치 |
| 응답 일부만 출력됨 | CLOB의 첫 구간만 출력했는지, 클라이언트 표시 길이 |

## 6. 재실행과 실습 정리

각 예제의 객체명을 확인하고 **팀 → Task → Tool → Agent → 프로파일** 순서로 정리합니다. 같은 이름을 다른 예제나 업무에서 공유하고 있다면 먼저 참조 관계를 확인합니다. 예제 끝의 정리 블록은 객체가 없을 때 `force => TRUE`로 처리하고, 다른 오류는 숨기지 않도록 구성했습니다.

RAG 인덱스 삭제는 벡터 데이터까지 제거할 수 있으므로 일반 Agent 정리와 분리합니다. 벡터 테이블과 임베딩 모델은 사용자 데이터이므로 자동으로 삭제하지 않습니다.

이 문서의 보강은 공식 문서와 예제 코드의 정적 대조를 기준으로 합니다. 실제 DB·Ollama에 접속한 실행 검증은 별도이며, 사용 RU와 모델에서 연결 → 단일 도구 → Team 순으로 확인합니다.
