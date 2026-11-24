# Oracle AI Agent 프로그램 읽기

[POC 소개](../README.md) · [구조와 역할](./ARCHITECTURE.md)

프로그램을 처음 읽을 때는 설치 순서, 외부에서 호출하는 진입점, Worker의 실제 업무 함수 순으로 살펴보면 된다. 객체명과 상태별 세부 값은 아래 표와 부록에 모았다. 실행 로직은 이번 문서 개정에서 변경하지 않았다.

## 1. 설치하면 무엇이 만들어지는가

먼저 모델 프로파일을 준비한다. Native Agent가 사용하는 조정 프로파일과, 상품/판매 SQL을 만드는 프로파일을 나눈다. 상품 조회용 프로파일의 대상은 PRODUCTS만으로 제한한다.

그다음 요청을 보관하는 테이블과 Native 호출별 추적 테이블을 만든다. 업무 처리 패키지, 공개 진입 패키지와 Tool용 함수, 취소 함수를 생성한 뒤 이 함수들을 Oracle Agent의 Tool로 등록한다. Task와 Agent를 정의하고 Team으로 연결하면 설치가 끝난다.

| 순서 | 파일 | 목적 |
|---|---|---|
| 전체 | [install.sql](../install.sql) | 하위 파일을 순서대로 실행하는 최초 설치 진입점 |
| 1 | [00_profiles.sql](../00_profiles.sql) | 기존 업무 프로파일 복제, 판매/상품 SQL 범위와 Native 모델 설정 |
| 2 | [01_state.sql](../01_state.sql) | POC_V2_RUNS: 원문·요구·승인·실행·결과·보고서 저장 |
| 3 | [01a_executions.sql](../01a_executions.sql) | POC_V2_EXECS: Native 호출별 상태와 Task 이력 저장 |
| 4 | [02_api.sql](../02_api.sql) | Worker가 사용하는 실제 업무 처리 패키지 |
| 5 | [03_gateway.sql](../03_gateway.sql) | 공개 진입·Native 제어·최종 반환 검증과 Tool 어댑터 |
| 6 | [03a_cancel.sql](../03a_cancel.sql) | 취소된 요청의 토큰을 폐기해 늦은 호출 차단 |
| 7 | [04_agents.sql](../04_agents.sql) | Tool·Task·Worker·Supervisor·Team 등록, 마지막 Team 비활성화 |
| 예제 | [05_examples.sql](../05_examples.sql) | 설치에 자동 포함하지 않는 질문·재개 호출 예제 |

각 SQL의 머리말에는 목적과 의존성을, 주요 함수 앞에는 처리 의도를 주석으로 설명했다. 기존 SH와 표준화·메타정보를 만드는 파일은 이 설치에 포함하지 않는다.

## 2. 사용자는 어디를 호출하는가

외부 진입점은 POC_V2_GATE.run과 resume이다. run은 새 사용자 turn을 저장하고 Native 처리를 시작한다. resume은 실제 사용자 답변을 검증한 뒤 요청 버전을 올려 이어 간다. 성공 응답을 만드는 public_result는 저장된 승인·실행·보고서가 같은 요청과 SQL에 대한 것인지 확인한다.

Gate 내부의 drive는 RUN_TEAM을 호출한다. 상태를 보고 Worker와 Task를 지정하고, state_variables에 명시적 요청 ID와 버전을 전달한다. start_round/record_round는 Native 실행 전후 상태와 이력을 남긴다. begin_runner/end_runner는 실행 토큰을 획득·해제한다.

Tool 입력은 원문이나 자유 형식 객체가 아니라 요청 ID 문자열이다. 세 어댑터 함수가 이를 Gate.dispatch의 STANDARD/QUERY/REVIEW 구분값에 연결한다. dispatch가 현재 상태에 맞는 업무 함수만 허용한다.

## 3. Worker의 업무는 어디에 구현되어 있는가

POC_V2_API는 표준화부터 보고서까지 실제 처리를 담당한다. 모델이 필요한 의미 해석·SQL 생성·검토와, 코드가 담당할 상태·소스·버전·실행 검사를 구분해 구현한다.

| 함수 | 처리 흐름에서의 의미 |
|---|---|
| start_request | 모델 호출 전에 원문을 저장하고 동일 turn 재전송을 구분 |
| standardize / clarify | 기존 사전·실제 후보 연결, 사용자 답변 확인과 이전 승인 무효화 |
| prepare | 의미 요구 JSON을 정리하고 데이터셋·필드를 확인한 뒤 SQL만 생성 |
| review | 실행 전 질문/SQL 대조와 승인, 실행 후 결과 구조 검토 |
| execute_sql | 승인 버전과 전체 SQL 일치를 확인하고 DBMS_SQL로 저장 SQL 실행 |
| final_report | 검토된 원시 결과와 기존 표시 규칙으로 보고서 작성 |
| inspect | 저장 상태를 진단용 JSON으로 읽기 |

ask는 Tool 모델 호출마다 별도 대화를 만든다. catalog/semantic_context는 메타정보를 문맥으로 구성한다. normalize_plan/check_sql은 데이터셋·필드·소스·상품 ID·출력 형태를 검사한다. obj는 CLOB 전체에서 JSON을 파싱하고 check_revision은 오래된 호출을 거절한다.

DBMS_CLOUD_AI.GENERATE는 요구/검토를 위한 chat과 SQL을 만들기 위한 showsql에 사용한다. 실행은 DBMS_SQL로 수행한다. DBMS_CLOUD_AI의 runsql로 새 SQL을 생성해 실행하지 않는다. SQL 전체 비교에는 DBMS_LOB.COMPARE를 사용한다.

## 4. Oracle Agent 객체는 어떻게 연결되는가

Tool은 실제 PL/SQL 함수와 입력 계약을 등록한다. Task는 수행할 작업과 사용할 Tool, Human Tool 허용 여부를 지정한다. Agent는 역할과 AI 프로파일을 지정한다. Team은 Agent와 Task를 연결하고 Supervisor를 선택한다.

일반 Task 3개는 대응 Tool 호출 후 Final Answer: DONE으로 끝내도록 지시한다. Human Task 2개는 같은 표준화·조회 Worker에 연결되며 실제 질문과 후보를 전달한다. Task의 Human 설정이 Agent 설정을 덮어쓸 수 있어 일반 Task는 false, Human Task는 true를 명시한다.

| Oracle API | 이 구현에서의 용도 |
|---|---|
| CREATE_PROFILE | 모델·endpoint·conversation·SQL object_list 설정 |
| CREATE/SET/CLEAR_CONVERSATION_ID | Native와 Tool 대화 생성·분리·복원 |
| CREATE_TOOL / CREATE_TASK / CREATE_AGENT | 함수 입력, 작업 지침, 역할 등록 |
| CREATE_TEAM | sequential Team, supervisor_agent, Worker/Task 연결 |
| RUN_TEAM / GET_VARIABLE | Native 실행과 명시적 요청 포인터 전달·조회 |
| GET_TEAM_STATE | Native 상태 관찰과 대기 대화 재사용 판단 |
| GET_DEFINITION | 배치된 객체의 CREATE 정의 추출 |
| ENABLE_TEAM / DISABLE_TEAM | 설치 후 실행 통제 |

API 준비는 저장소의 [공통 환경 구성](../../OnPremises_Setup.md)을 먼저 따른다. 공식 세부 참조는 [Agent 패키지](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/dbms-cloud-ai-agent-package.html), [Supervisor Team](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/how-to-use-select-ai-supervisor-agent-teams.html), [기능 지원표](https://docs.oracle.com/en/database/oracle/oracle-database/26/saicm/index.html)에 있다. 공통 참조가 Autonomous 문서로 연결되면 온프레미스 RU 지원 여부도 함께 확인한다.

## 부록. 상태·검사·제한

| 구분 | 구현 값·확인 항목 |
|---|---|
| 정상 실행형 | NEW → STANDARDIZED → SQL_GENERATED → PRECHECKED → EXECUTED → RESULT_REVIEWED → SUCCEEDED |
| 처리 중 | PREPARING, EXECUTING |
| 사용자 확인 | NEEDS_CLARIFICATION, 실제 답변 후 revision 증가 |
| 단계 실패 | PREPARE_FAILED, PRECHECK_FAILED, EXECUTE_FAILED, POSTCHECK_FAILED |
| 종료 | FAILED, UNSUPPORTED 또는 검증된 SUCCEEDED |
| Tool 단계 예산 | 요청당 최대 20회 |
| Native 재진입 | 요청당 최대 12회, 무진행 2회 제한 |
| 요청 deadline | 실행 시작/재개 후 15분 |
| 최종 검증 | 요청·SQL·보고서 버전, 전체 SQL CLOB 동일성, validation_contract=2 검토 승인 |
| 실행 없는 결과 | SHOWSQL/EXPLAINSQL은 result_json=NULL, execution_attempts=0 |

이 한도는 DB 검사 경계에 적용된다. LLM 내부의 잘못된 도구명 반복 등 모든 행동을 세는 것은 아니므로 클라이언트의 시간 제한도 사용한다. 취소 함수는 Oracle 내부 Task 이력을 수정하지 않는다.
