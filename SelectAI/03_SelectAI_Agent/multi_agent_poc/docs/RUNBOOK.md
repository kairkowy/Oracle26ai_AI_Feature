# 직접 실행하기

[POC 소개](../README.md) · [프로그램 설명](./PROGRAMS.md)

이 가이드는 기존 LAB에서 직접 질문을 실행하는 순서를 먼저 설명한다. 새 환경을 설치하는 경우에는 마지막의 **신규 환경 준비와 설치**를 먼저 수행한다. 아래 예시는 SQL*Plus 기준이다.

## 1. 기존 LAB의 준비 상태 확인

접속 정보는 기존 LAB 계정을 사용하고 암호는 실행 도구에서 입력한다. 먼저 v2 객체의 컴파일 오류와 Team 상태를 확인한다.

~~~sql
SELECT object_name, object_type, status FROM user_objects
 WHERE object_name LIKE 'POC_V2%' AND status <> 'VALID';

SELECT name, type, line, position, text FROM user_errors
 WHERE name LIKE 'POC_V2%' ORDER BY name, sequence;

SELECT agent_team_name, status FROM user_ai_agent_teams
 WHERE agent_team_name = 'POC_V2_TEAM';
~~~

앞의 두 조회는 오류 행이 없어야 한다. Team이 DISABLED이면 설정을 확인한 뒤 활성화한다. 기존 객체가 있는 LAB에서 install.sql을 다시 실행할 필요는 없다.

~~~sql
EXEC DBMS_CLOUD_AI_AGENT.ENABLE_TEAM(team_name => 'POC_V2_TEAM');
SET LONG 200000
SET LONGCHUNKSIZE 200000
~~~

## 2. 첫 질문으로 상품 조회

~~~sql
SELECT POC_V2_GATE.run(
 '프로 메이플 배트의 상품 ID와 상품명과 정가를 조회해줘.',
 'manual-20261124-01', 'turn-001'
) AS response FROM dual;
~~~

호출은 JSON을 반환한다. status가 succeeded이면 report에서 표시 답변을 보고 result.rows에서 원시 결과를 확인한다. 다음은 핵심 필드만 발췌한 응답 형태다. 실제 report 전문과 요청 ID는 실행마다 다르다.

~~~json
{
  "status": "succeeded",
  "result": {
    "rows": [
      {"product_id": 129, "product_name": "Pro Maple Bat", "list_price": 192.99}
    ]
  }
}
~~~

위 상품 기준값은 11월 20일 시험 결과다. 현재 데이터와 직접 비교하려면 다음 SQL을 실행한다.

~~~sql
SELECT prod_id, prod_name, prod_list_price
  FROM products WHERE prod_id = 129;
~~~

## 3. 판매 집계 질문과 기준 SQL 대조

~~~sql
SELECT POC_V2_GATE.run(
 '미국 여자 고객이 구매한 야구용품의 매상 합계를 조회해줘.',
 'manual-20261124-01', 'turn-002'
) AS response FROM dual;
~~~

result.rows의 revenue_sum을 다음 기준 SQL과 대조한다. 11월 20일 동일 조건의 합계는 6,063,776.96이었다. 이번 문서에서 “미국”으로 정리한 문장으로는 새로 DB 시험을 실행하지 않았다.

~~~sql
SELECT SUM(s.amount_sold) AS revenue_sum
  FROM sales s
  JOIN products p ON p.prod_id = s.prod_id
  JOIN customers c ON c.cust_id = s.cust_id
  JOIN countries n ON n.country_id = c.country_id
 WHERE n.country_name = 'United States of America'
   AND c.cust_gender = 'F'
   AND p.prod_category = 'Baseball';
~~~

## 4. 같은 상품명에 여러 후보가 있는 경우

~~~sql
SELECT POC_V2_GATE.run(
 'Team shirt의 상품 ID와 상품명과 정가를 조회해줘.',
 'manual-20261124-01', 'turn-003'
) AS response FROM dual;
~~~

needs_human 응답의 question과 candidates를 확인한다. 실제 응답에 있는 상품 중 사용자가 원하는 ID를 골라 재개한다. 아래는 request_id, revision, 선택한 product_id를 입력받는 SQL*Plus 예다.

~~~sql
SET DEFINE ON
ACCEPT request_id CHAR PROMPT '응답의 request_id: '
ACCEPT request_revision NUMBER PROMPT '응답의 revision: '
ACCEPT selected_product_id NUMBER PROMPT '선택한 실제 product_id: '

SELECT POC_V2_GATE.resume(
 '&request_id', &request_revision, '&selected_product_id'
) AS response FROM dual;

UNDEFINE request_id
UNDEFINE request_revision
UNDEFINE selected_product_id
~~~

응답에 없는 ID를 예제값으로 고정 선택하지 않는다. 현재 후보 표시 한도는 5개이므로 원하는 상품이 없으면 더 정확한 상품명으로 새 질문을 한다.

선택 후에는 revision이 증가하고 해당 ID의 결과가 나오는지 확인한다. 11월 20일 자동 시험에서는 후보 41을 골라 Team shirt, 정가 44.99를 확인했다. 이 시험은 실제 사람이 UI에서 답한 시험과 구분한다. 상위 Team 대기 상태 문제 때문에 Native 상태만 보고 사용자 확인이 끝났다고 판단하면 안 된다.

## 5. 데이터를 실행하지 않는 두 질문

~~~sql
-- 네 번째 질문: SQL 작성만 요청한다.
SELECT POC_V2_GATE.run(
 '미국 여자 고객이 구매한 야구용품의 매상 합계 SQL만 작성해줘. 실행하지 말아줘.',
 'manual-20261124-01', 'turn-004'
) AS response FROM dual;

-- 다섯 번째 질문: SQL 설명만 요청한다.
SELECT POC_V2_GATE.run(
 '미국 여자 고객이 구매한 야구용품의 매상 합계 SQL을 설명해줘. 실행하지 말아줘.',
 'manual-20261124-01', 'turn-005'
) AS response FROM dual;
~~~

이 두 경로의 전체 Native 회귀 검증은 완료하지 않았다. 직접 실행할 때는 문장·SQL/설명뿐 아니라 **데이터 실행이 없었는지** 확인한다. 요청의 execution_attempts는 0, result_json은 NULL이어야 한다.

~~~sql
SELECT client_turn_id, requested_action, state, execution_attempts,
       CASE WHEN result_json IS NULL THEN 'NO_RESULT' ELSE 'HAS_RESULT' END AS result_state
  FROM POC_V2_RUNS
 WHERE conversation_id = 'manual-20261124-01'
 ORDER BY created_at;
~~~

## 6. 재실행과 오류 확인

같은 turn과 같은 원문을 다시 보내면 기존 요청을 읽는다. 새로 시험하려면 새로운 turn ID 또는 대화 ID를 사용한다. 같은 turn에 원문만 바꾸면 충돌을 거절한다. 원시 SELECT AI AGENT 대신 Gate.run/resume을 사용해야 최종 저장 결과 검증을 거친다.

| 응답 status | 확인할 내용 |
|---|---|
| succeeded | report, 원시 result.rows 및 기준 SQL과의 일치 |
| needs_human | 실제 question/candidates와 사용자 선택 |
| running | 동일 요청이 아직 처리 중인지 |
| failed / unsupported / error | error_code 및 아래 저장 오류. 결과 0건과 구분 |

~~~sql
SELECT request_id, revision, state, flow_steps, execution_attempts, last_error
  FROM POC_V2_RUNS ORDER BY created_at DESC FETCH FIRST 10 ROWS ONLY;

SELECT round_no, state_before, state_after, native_state,
       started_at, ended_at, error_message
  FROM POC_V2_EXECS WHERE request_id = :request_id ORDER BY round_no;
~~~

클라이언트에서 DB 호출을 취소한 뒤 늦게 오는 Tool 호출을 막으려면 POC_V2_CANCEL_FN(request_id, revision)을 사용한다. 이 함수는 요청을 폐기하는 함수이며 실행 중 SQL 자체의 중단은 드라이버 break()가 담당한다. NOWAIT 경합이 있으면 현재 트랜잭션이 끝난 뒤 상태를 재확인한다.

## 신규 환경 준비와 설치

일반 SH만 준비한 환경에는 표준화·업무 메타정보가 없으므로 이 폴더만 설치해서 바로 실행할 수 없다. 다음 자산을 먼저 확인한다.

| 준비사항 | 내용 |
|---|---|
| DB·패키지 | Native Supervisor를 지원하는 RU와 DBMS_CLOUD_AI/DBMS_CLOUD_AI_AGENT, 객체 생성·실행·조회 권한 |
| 원천 데이터 | PRODUCTS, SALES, CUSTOMERS, COUNTRIES, TIMES |
| 기존 표준화 자산 | POC_STD_* 3개, POC_QUESTION_TERM, POC_STANDARD, POC_PRODUCT_RESOLVE |
| 기존 메타정보 | POC_AI_* 업무 테이블 7개, POC_PROMPT, POC_SETTING |
| 업무 모델 프로파일 | POC_AI_PROFILE. 검증 당시 gemma2:9b |
| Native 모델·연결 | granite4.1:8b, DB에서 접근 가능한 Ollama endpoint·ACL·프록시 |

패키지·권한·네트워크 준비는 [공통 환경 구성](../../OnPremises_Setup.md)을 참고한다. 00_profiles.sql의 http://service-ollama/v1은 LAB 서비스 주소 예시이므로 새 환경에 맞게 확인한다. SQL 프로파일은 기존 프로파일의 속성을 복제한다.

SQL*Plus의 현재 디렉터리를 이 POC 폴더로 지정한 뒤 실행한다. DB 암호는 접속 도구에서 입력하며 저장소에 기록하지 않는다.

~~~sql
@install.sql
~~~

설치 순서는 프로파일 → 요청 테이블 → 실행 추적 테이블 → 업무 패키지 → 진입 패키지 → 취소 함수 → Agent 객체다. 마지막에 Team을 DISABLED로 둔다. 컴파일 확인 후 이 가이드 처음의 활성화와 질문 실행을 진행한다. install.sql은 최초 설치용이며 기존 v2 테이블을 삭제하거나 마이그레이션하지 않는다.

## 부록. Node 클라이언트와 자동 시험

Node.js와 package.json의 oracledb 의존성을 준비한 뒤 node client.cjs를 실행하고 한 줄 JSON을 표준입력으로 전달한다. 자격 증명은 user/password/connectString, 새 질문은 question/conversation_id/client_turn_id, 재개는 request_id/revision/human_answer를 사용한다. 실제 암호 JSON은 파일·명령 인수·버전 관리에 남기지 않는다.

timeoutMs 기본값은 600000ms다. 드라이버 callTimeout 외에 별도의 경과 시간 타이머와 잘못된 위임 감시를 사용한다. 취소와 DB 정리에 시간이 추가되므로 타이머 시각이 즉시 종료 시각은 아니다.

tests/components.cjs는 보호 계약과 동시성을, tests/native.cjs는 실제 이력·상태 순서·보고서와 독립 SQL을 비교한다. tests/human.cjs는 실제 후보를 자동 선택하고 상위 Team 대기를 엄격히 검사한다. 이 엄격 검사의 실패를 통과로 바꾸지 않는다. 자동 시험은 POC 시험 요청을 생성하므로 운영 계정에서 실행하지 않는다.
