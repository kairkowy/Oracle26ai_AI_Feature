# 구성과 자연어 답변 처리 흐름

[목차](../README.md) · [SVG 구조도](../diagrams/architecture.svg)

## Native Agent와 애플리케이션의 경계

Gate는 PL/SQL 제어 계층이고 Supervisor는 Oracle Native Agent다. Gate가 업무 결과를 직접 계산하는 대체 파이프라인을 실행하지 않는다. 실제 표준화·생성·검토·실행·보고는 Native Worker가 등록 Tool을 호출할 때만 진행한다. 다만 다음 단계, 허용 상태, 공개할 결과의 최종 판단은 DB 코드가 담당한다.

| Agent | 일반 Task / Tool | 수행 업무 |
|---|---|---|
| POC_V2_SUPERVISOR | 내장 ORA$DELEGATE_TOOL | Gate가 준 Agent/Task 이름과 요청 ID 문자열을 전달. |
| POC_V2_STANDARD | STANDARD_TASK / STANDARD_TOOL → STANDARD_FN | 원문의 표준화 문맥 저장. |
| POC_V2_QUERY | QUERY_TASK / QUERY_TOOL → QUERY_FN | 상태에 따라 prepare, execute_sql, final_report 실행. |
| POC_V2_REVIEW | REVIEW_TASK / REVIEW_TOOL → REVIEW_FN | 상태에 따라 실행 전/후 review 실행. |
| 기존 Standard/Query Worker | STANDARD_HUMAN_TASK / QUERY_HUMAN_TASK | 실제 질문과 후보를 Human Tool로 제시. 별도 Worker를 만들지 않음. |

각 일반 Task는 Tool Observation을 받은 뒤 **Final Answer: DONE**으로 종료하도록 지시한다. 한 단계 위임은 모델 지침이며 엄격한 1회 호출 보장은 아니다. 실제 재호출은 코드 상태 검사·잠금·예산으로 방어한다. 위임의 task_input은 객체가 아닌 **32자리 요청 ID 문자열**이다.

## 일반 조회 흐름

1. 사용자가 원문·conversation_id·client_turn_id로 Gate.run을 호출한다. LLM 호출 전에 NEW 요청을 INSERT/COMMIT한다. 같은 대화·turn의 동일 원문 재전송만 기존 ID에 연결한다.
2. Gate가 request_id/revision을 Native state_variables로 전달하고 Supervisor가 Standard Worker를 호출한다.
3. Standard Tool이 POC_STANDARD.scan_question, question_hints와 POC_PRODUCT_RESOLVE를 호출해 실기준값·후보·업무 카탈로그를 context_json에 저장한다. 후보가 유일하면 STANDARDIZED다.
4. Query Worker의 prepare가 의미 문맥으로 요구 JSON을 생성한다. dataset_key, action, filters, group_keys, required_outputs, 표시명, 행 한도, 미확정 항목을 해석한다. 필드 소속과 상품 ID 조건을 메타데이터로 검증한다.
5. DBMS_CLOUD_AI.GENERATE의 showsql로 SQL만 생성해 SQL_GENERATED로 저장한다. 상품 목록은 PRODUCTS 전용 프로파일을 사용한다. 집계 요구 없이 판매 테이블을 조인해 상품이 중복되는 경로를 거절한다.
6. Review Worker가 SELECT 허용 규칙, 소스, 컬럼, 집계 기준과 질문 의미를 검토한다. 승인 시 PRECHECKED 및 revision/SQL version/SQL 전체 CLOB를 저장한다.
7. RUNSQL/NARRATE의 실행 허용 요청만 Query Worker가 execute_sql로 처리한다. 행 잠금을 유지한 채 승인 SQL과 현재 SQL을 비교하고 DBMS_SQL로 **저장된 SQL 그대로** 실행한다. SQL 생성 모델을 다시 호출해 실행문을 바꾸지 않는다.
8. Review Worker가 결과 컬럼·행 형태·상품 고유 키 중복 등을 사후 검토해 RESULT_REVIEWED로 전이한다. Query Worker가 원시 결과와 기존 한글 표시 규칙으로 보고서를 저장한다.
9. Gate.public_result가 보고서·승인·실행 버전, 검토 계약과 SQL CLOB 일치를 확인해 SUCCEEDED 응답을 만든다. Native의 자유 문장이나 raw_agent_output을 사용자 보고서로 대체하지 않는다.

정상 실행형 상태는 **NEW → STANDARDIZED → SQL_GENERATED → PRECHECKED → EXECUTED → RESULT_REVIEWED → SUCCEEDED**다. PREPARING/EXECUTING은 처리 중 상태이며 실패 시 PREPARE_FAILED, PRECHECK_FAILED, EXECUTE_FAILED, POSTCHECK_FAILED 또는 FAILED로 남는다. 재시도는 상태·정책·예산이 허용하는 경우에만 가능하다.

## 실행 없는 요청

SHOWSQL은 생성·사전 검토 후 SQL을 반환한다. EXPLAINSQL은 실행 없이 SQL 설명을 검토·보고한다. 두 경로는 result_json=NULL, execution_attempts=0이어야 최종 게이트를 통과한다. 원문의 “SQL만”, “실행하지 말아”는 실행 허용을 다시 제한한다. NARRATE는 검증된 조회 결과를 해설하는 실행형 경로다. 전체 Native 회귀 완료 범위는 [검증 결과](VALIDATION.md)와 구분한다.

## 모호한 상품과 사용자 확인

실제 상품명이 같은 후보가 여러 개이면 NEEDS_CLARIFICATION으로 저장한다. 응답에는 실제 product_id/name/display_name과 전체 후보 수·잘림 여부가 담긴다. 현재 정책은 최대 5개를 표시한다. 보이지 않는 후보를 임의 선택하지 않으며 정확한 상품명으로 새 질문을 할 수 있다.

실제 사용자가 선택한 ID를 Gate.resume(request_id, revision, answer)에 전달하면 후보 존재를 검증하고 revision을 증가시킨다. 이전 승인·결과를 무효화하고 선택된 ID만 문맥에 남긴다. 사용자 답변을 LLM이 발명해 저장하는 CLARIFY Tool은 없다.

현재 LAB 구성은 Human Worker만 WAITING_FOR_HUMAN이고 상위 Team은 SUCCEEDED로 반환되는 제약이 있다. Gate는 저장된 NEEDS_CLARIFICATION을 진실의 기준으로 삼는다. 재개 시 상위 Team이 실제 대기이면 같은 Native 대화를 사용하고, 아니면 새 Native 대화에서 저장 요청을 이어 간다. 이 방식의 API 검증과 상위 Native 대기 실패를 동일한 성공으로 취급하지 않는다.

## 재시도·동시성·종료

요청당 Tool 단계 최대 20회, Native 호출 최대 12회, 시작/재개 후 deadline 15분, 무진행 2회 제한을 적용한다. 이는 DB 검사가 가능한 경계의 한도이며 LLM 내부의 모든 토큰/잘못된 도구명 반복을 직접 세지 않는다. 클라이언트는 드라이버 callTimeout과 별도 경과 시간 break 타이머를 갖는다. 취소 함수는 요청을 FAILED로 만들고 runner 토큰을 무효화한다. 취소와 DB 정리에 걸리는 시간 때문에 타이머 시각이 즉시 종료 시각은 아니다.
