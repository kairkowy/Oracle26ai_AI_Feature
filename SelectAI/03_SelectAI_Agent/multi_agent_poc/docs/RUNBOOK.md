# 실행 방법

[목차](../README.md) · [프로그램 설명](PROGRAMS.md)

## 1. 사전 준비

1. 지원 RU의 Oracle AI Database에서 DBMS_CLOUD_AI와 DBMS_CLOUD_AI_AGENT 설치·실행 권한 및 Native Supervisor 기능을 확인한다. 패키지 설치/ACL/프록시는 [공통 환경 구성](../../OnPremises_Setup.md)을 따른다.
2. 기존 LAB의 PRODUCTS, SALES, CUSTOMERS, COUNTRIES, TIMES와 POC_STD_*, POC_QUESTION_TERM, POC_AI_* 업무 메타, POC_SETTING, POC_PROMPT, POC_STANDARD, POC_PRODUCT_RESOLVE, POC_AI_PROFILE을 준비한다. 일반적인 SH 원본만으로는 이 POC의 확장 표준화 정보가 준비되지 않는다.
3. 실행 계정에서 재사용 테이블 조회와 패키지/프로파일 사용이 가능해야 한다. 새 v2 테이블·패키지·함수·Agent 객체 생성 권한이 필요하다. 이 문서는 공용 스키마에 광범위 권한을 자동 부여하지 않는다.
4. DB에서 접근 가능한 Ollama에 granite4.1:8b와 기존 POC_AI_PROFILE 모델을 준비한다. 검증 모델은 gemma2:9b다. 00_profiles.sql의 http://service-ollama/v1은 LAB 서비스 주소 예시이므로 실제 endpoint에 맞게 검토한다. 일반 SQL 프로파일은 기존 프로파일 속성을 복제한다.

설치는 기존 데이터에 대한 INSERT/UPDATE를 수행하지 않는다. 기존 표준화 seed와 원본 DB 접속 정보·암호는 이 폴더에 포함하지 않는다.

## 2. 최초 설치

SQL*Plus를 이 폴더에서 시작하고 기존 LAB 계정으로 접속한다. 비밀번호는 도구의 입력 프롬프트를 사용한다.

~~~sql
@install.sql

SELECT object_name, object_type, status FROM user_objects
 WHERE object_name LIKE 'POC_V2%' AND status <> 'VALID';
SELECT name, type, line, position, text FROM user_errors
 WHERE name LIKE 'POC_V2%' ORDER BY name, sequence;

-- 컴파일/환경 검토 후 활성화. 설치 직후는 DISABLED다.
EXEC DBMS_CLOUD_AI_AGENT.ENABLE_TEAM(team_name => 'POC_V2_TEAM');
~~~

설치 순서는 00_profiles → 01_state → 01a_executions → 02_api → 03_gateway → 03a_cancel → 04_agents다. 기존 v2 객체가 있으면 CREATE가 실패할 수 있다. install.sql은 반복 설치·마이그레이션 도구가 아니며 기존 테이블을 DROP하지 않는다. 같은 계정에 이미 검증 구현이 배치돼 있으면 재설치 대신 상태 확인과 예제 호출부터 수행한다.

## 3. 질문과 응답

~~~sql
SET LONG 200000
SET LONGCHUNKSIZE 200000
SELECT POC_V2_GATE.run(
 '미합중국 여자 고객이 구매한 야구용품의 매상 합계를 조회해줘.',
 'ai-session-001','turn-002'
) AS response FROM dual;
~~~

| 응답 status | 처리 |
|---|---|
| succeeded | report와 검증된 result.rows를 표시. SQL 표시 요청이면 sql도 반환 가능. |
| needs_human | question/candidates를 그대로 표시하고 실제 답변을 기다림. |
| running | 같은 turn이 처리 중. 임의의 새 질문으로 재전송하지 않음. |
| failed / unsupported / error | 오류를 결과 0건으로 표시하지 않음. error_code와 저장 상태 확인. |

완료 후 같은 turn과 원문을 재전송하면 기존 결과를 읽는다. 새로운 조회에는 새 turn ID를 사용한다. 같은 turn에 원문을 바꿔 보내면 충돌을 거절한다.

## 4. 실제 후보 선택 후 재개

~~~sql
SELECT POC_V2_GATE.run(
 'Team shirt의 상품 ID와 상품명과 정가를 조회해줘.',
 'ai-session-001','turn-003'
) AS response FROM dual;

-- 위 응답의 실제 request_id와 revision 및 실제 후보 ID를 사용한다.
-- 아래 ID 41은 검증 데이터의 예시다. 응답에 없는 ID를 고정 선택하면 안 된다.
SELECT POC_V2_GATE.resume('반환된_32자리_REQUEST_ID',1,'41')
 AS response FROM dual;
~~~

후보가 잘렸고 원하는 상품이 없으면 더 정확한 상품명으로 새 질문을 한다. Human Worker 상태와 상위 Team 상태 불일치가 있으므로 Native GET_TEAM_STATE만 보고 선택이 끝났다고 판단하지 않는다. Gate의 needs_human과 저장 NEEDS_CLARIFICATION이 기준이다.

## 5. Node 실행 클라이언트

Node.js와 package.json의 oracledb 의존성을 준비한다(npm install). client.cjs는 한 줄 JSON을 **표준입력**으로 받는다. 애플리케이션/비밀 관리 도구가 다음 필드를 공급한다. 실제 비밀번호 JSON을 파일·명령 인수·버전 관리에 남기지 않는다.

| 필드 | 설명 |
|---|---|
| user / password / connectString | 실행 계정의 접속 자격 증명. |
| question / conversation_id / client_turn_id | 새 요청. |
| request_id / revision / human_answer | 사용자 답변 재개 시 사용. |
| timeoutMs | 클라이언트 호출·경과 시간 제한. 기본 600000ms. |

node client.cjs에 표준입력을 연결한다. Oracle 드라이버가 별도 경로에 있으면 첫 번째 명령 인수로 지정한다. client는 드라이버 callTimeout, 잘못된 NULL 위임 입력 감시, 별도 경과 시간 break 타이머를 사용한다. 취소가 즉시 완료되는 것은 아니며 실제 DB 정리 시간이 추가된다.

## 6. 상태 확인·취소

~~~sql
SELECT request_id, revision, state, requested_action,
       flow_steps, execution_attempts, last_error
  FROM POC_V2_RUNS ORDER BY created_at DESC FETCH FIRST 10 ROWS ONLY;

SELECT round_no, revision, state_before, state_after, native_state,
       started_at, ended_at, error_message
  FROM POC_V2_EXECS WHERE request_id = :request_id ORDER BY round_no;

-- 실행 중 DB 호출은 클라이언트 드라이버에서 break()한다.
-- 그 뒤 동일 요청의 늦은 후속 Tool 호출을 차단한다.
SELECT POC_V2_CANCEL_FN(:request_id,:revision) AS response FROM dual;
~~~

NOWAIT 경합이면 현재 트랜잭션이 끝난 뒤 상태를 다시 확인한다. Oracle 내부 Agent 이력 테이블을 직접 UPDATE하거나 성공으로 위조하지 않는다. 시험 재실행은 새로운 conversation/turn ID와 별도 결과 파일을 사용한다.

## 7. 시험 도구

tests/components.cjs는 보호 계약·동시 실행을 검사한다. tests/native.cjs는 실제 Native 경로의 이벤트 순서·보고서 동일성·독립 referenceSql 비교를 수행한다. tests/human.cjs는 실제 반환 후보 중 하나를 자동 선택해 API 재개를 확인하고 상위 Team 대기도 엄격히 검사한다. 현재 Human 엄격 검사는 상위 상태 문제 때문에 실패할 수 있으며 통과로 바꾸면 안 된다. 시험 입력 형식은 각 파일의 cfg 사용 부분과 [검증 결과](VALIDATION.md)를 함께 참고한다. 테스트는 POC_V2_* 시험 요청을 생성하므로 운영 계정에서 실행하지 않는다.
