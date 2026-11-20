# Oracle AI Agent 프로그램 설명

[목차](../README.md)

## 각 SQL 파일

| 파일 | 생성/사용 객체 | 내용·실행 시점 |
|---|---|---|
| [install.sql](../install.sql) | 하위 스크립트 호출 | 최초 설치 순서 정의. 데이터 적재·정리 스크립트 아님. |
| [00_profiles.sql](../00_profiles.sql) | SQL_PROFILE, PRODUCTS_PROFILE, AGENT_PROFILE | 기존 SQL 프로파일 속성을 복제하고 SH 5개/PRODUCTS만으로 object_list를 제한. Native Granite 프로파일 생성. endpoint 검토 필요. |
| [01_state.sql](../01_state.sql) | POC_V2_RUNS | 사용자 turn 유일 키, 상태·revision, 승인/실행 CLOB, 문맥·결과·이벤트, 실행 토큰과 예산 생성. |
| [01a_executions.sql](../01a_executions.sql) | POC_V2_EXECS | 요청 FK와 round 유일 키, Native 호출 이력·Task 스냅샷 저장. |
| [02_api.sql](../02_api.sql) | POC_V2_API spec/body | 표준화·요구 해석·SQL 생성·사전/사후 검토·동일 SQL 실행·보고 엔진. |
| [03_gateway.sql](../03_gateway.sql) | POC_V2_GATE, STANDARD_FN, QUERY_FN, REVIEW_FN | 공개 API, Native 제어, Tool 계약, 최종 검증 및 함수 어댑터. |
| [03a_cancel.sql](../03a_cancel.sql) | POC_V2_CANCEL_FN | revision 검사 후 요청 폐기·토큰 무효화. 실제 실행 취소와 구분. |
| [04_agents.sql](../04_agents.sql) | Tool/Task/Agent/Team | 공개 GET_DEFINITION 기반 Native 객체 정의. 설치 마지막 Team DISABLE. |
| [05_examples.sql](../05_examples.sql) | 기존 공개 API 호출 | 질문, SQL만 작성, 후보 선택, 진단 조회 예. 설치에 자동 포함하지 않음. |

모든 SQL은 파일 머리말에 목적·의존성/주의점을 설명한다. 주요 PL/SQL 함수 앞에도 기능과 검증 의도를 주석으로 덧붙였다. 주석 추가로 SQL 로직을 바꾸지는 않았다.

## POC_V2_API 주요 함수

| 함수 | 처리 |
|---|---|
| start_request | 원문 보존·요청 초기화·turn 멱등성. |
| standardize / clarify | 기존 사전·실상품 후보 문맥 저장, 실제 답변 검증과 승인 무효화. |
| prepare | 의미 요구 JSON → dataset/field 검증 → showsql 생성. action과 원문 실행 금지 제한 적용. |
| review | PRECHECKED 승인과 실행 결과 RESULT_REVIEWED 검토. 검토 계약 validation_contract=2 사용. |
| execute_sql | 승인 revision/SQL version/CLOB 전체 비교, 행 잠금 아래 DBMS_SQL 실행·원시 JSON 저장. |
| final_report | 저장된 원시 행과 기존 표준화 표시 함수로 보고서 작성·report_revision 고정. |
| inspect | 저장 업무 상태 읽기. 공개 최종 응답 검증을 대신하지 않음. |

내부 catalog/semantic_context/normalize_plan/check_sql은 메타데이터 제약을 적용한다. ask는 Tool용 대화를 매번 분리한다. event/obj/check_revision은 이력·CLOB 파싱·revision 방어를 맡는다. DBMS_CLOUD_AI의 runsql로 SQL을 다시 생성해 실행하는 경로는 사용하지 않는다.

## POC_V2_GATE 주요 함수

| 함수·프로시저 | 처리 |
|---|---|
| run / resume | 새 요청/실제 사용자 확인 진입. |
| next_worker / status | 저장 상태 → 다음 담당자·작업·실제 후보 제어 JSON. |
| claim_step / dispatch | 활성 요청·revision·단계 예산 검사 후 허용 Worker만 실행. |
| begin_runner / start_round | 실행 토큰·Native 대화 ID·호출 예산 획득. |
| drive | RUN_TEAM 호출 반복. 명시적 state_variables/instruction_variables 전달. |
| record_round / end_runner | 공개 Native Task 스냅샷 저장 및 토큰 일치 실행 종료. |
| public_result | 승인/실행/보고서 버전·전체 SQL·사전/사후 검토 계약을 확인해 최종 응답 공개. |

STANDARD_FN/QUERY_FN/REVIEW_FN은 request_id를 받아 Gate.dispatch의 Worker 구분값에 연결하는 얇은 어댑터다. Oracle Tool은 이 함수를 실행한다.

## 사용한 Oracle 프로그램/API

| API | POC 용도 |
|---|---|
| DBMS_CLOUD_AI.CREATE_PROFILE | 모델, endpoint, conversation, SQL object_list 구성. |
| DBMS_CLOUD_AI.CREATE/SET/CLEAR_CONVERSATION_ID | Native 실행 및 Tool 모델 문맥의 명시적 분리·복원. |
| DBMS_CLOUD_AI.GENERATE | chat 기반 요구/검토, showsql 기반 SQL 생성. |
| DBMS_CLOUD_AI_AGENT.CREATE_TOOL | PL/SQL 함수·request_id 입력 계약을 Native 도구로 등록. |
| CREATE_TASK / CREATE_AGENT | 작업 지침·가용 Tool·Human 허용 여부·역할·프로파일 정의. Task Human 속성이 Agent 설정을 덮어쓸 수 있어 일반 Task에서는 false를 명시. |
| CREATE_TEAM | sequential Team과 supervisor_agent, 세 Worker의 Task 연결, long_term_memory_length=1 구성. |
| RUN_TEAM | 단계별 Native 위임 실행 및 실제 대기 실행 재개. 반환 CLOB는 최종 데이터의 신뢰 근거가 아님. |
| GET_VARIABLE | state_variables의 request_id/revision 포인터 조회. |
| GET_TEAM_STATE | Native 상태 관찰 및 대기 재개 여부 판정. 저장 업무 승인 상태를 대체하지 않음. |
| GET_DEFINITION | 실제 배치된 객체의 재현 가능한 CREATE 정의 추출. |
| ENABLE_TEAM / DISABLE_TEAM | 설치 후 활성화와 실행 통제. |
| DBMS_SQL | 저장된 SQL parse/describe/execute/fetch. 출력 타입에 따라 JSON 행 구성. |
| DBMS_LOB.COMPARE | 암호화 해시 권한 없이 승인/현재/실행 SQL CLOB 전체 동일성 비교. |

공식 문서: [Agent 패키지](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/dbms-cloud-ai-agent-package.html), [Supervisor Team](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/how-to-use-select-ai-supervisor-agent-teams.html), [온프레미스 기능 지원표](https://docs.oracle.com/en/database/oracle/oracle-database/26/saicm/index.html). 공통 API 문서는 Autonomous 참조로 연결될 수 있으므로 온프레미스 RU 지원표와 실제 패키지 시그니처를 함께 확인한다.
