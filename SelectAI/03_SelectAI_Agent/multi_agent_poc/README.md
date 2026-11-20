# AI 기반 자연어 데이터 조회 Multi-Agent POC

Oracle AI Database 26ai의 Native Select AI Agent와 기존 판매 이력·표준화 사전·업무 메타데이터를 연결한다. 사용자가 한국어로 질문하면 **표준화 → SQL 생성 → 실행 전 검토 → 승인한 SQL 실행 → 결과 검토 → 답변**으로 처리한다.

**Supervisor 1개와 Worker 3개**를 사용한다. 모델의 자유 문장을 정답으로 바로 반환하지 않고, DB에 저장한 요청·승인·실행 결과를 코드에서 검증해 반환하는 것이 핵심이다. 업무 영역과 관계없이 활용할 수 있는 AI 데이터 조회 구조를 검증한다.

## POC 의도·목표·범위

| 구분 | 설명 |
|---|---|
| 의도 | 사용자가 DB 컬럼명과 영문 기준값을 몰라도 업무 표현으로 데이터를 조회하도록 한다. |
| 목표 1 | 한글명·동의어·코드 표현을 실제 기준값/상품 ID에 연결하고 모호하면 사람에게 확인한다. |
| 목표 2 | 질문의 데이터셋·필터·집계 기준을 메타데이터와 대조하고, 검토한 SQL과 실행 SQL의 동일성을 보장한다. |
| 목표 3 | 서로 다른 Agent가 명시적 요청 ID로 협업하고 재시도·중복 호출·오래된 승인을 차단하는지 검증한다. |
| 포함 | SH 상품 기준정보, 판매 이력의 고객 성별·국가·상품분류·시간 기반 조회/집계, 요청별 상태와 추적 이력. |
| 데이터 원칙 | 기존 LAB 데이터를 재사용한다. SH·표준화·메타데이터를 이 설치에서 생성하거나 재적재하지 않는다. |
| 제외 | 데이터 변경 DML/DDL, 환율 변환, 임의 스키마 자동 개방, 운영 성능 보증, 질문 사이 지시어의 자동 연결. |

검증 환경은 DB **23.26.4.0.0**, Ollama **0.17.7**이다. Native 조정은 **granite4.1:8b**, Tool 내부 요구 해석·SQL 생성·검토는 기존 **gemma2:9b** 프로파일을 사용했다. 따라서 Granite 단독 Text-to-SQL 성능 시험이 아니다. 지원 API는 설치 RU와 [온프레미스 환경 구성](../OnPremises_Setup.md)을 확인한다.

## POC 구조

![AI Multi-Agent 구조](./diagrams/architecture.svg)

[SVG 원본](./diagrams/architecture.svg) · [구성 및 처리 흐름](./docs/ARCHITECTURE.md) · [데이터·표준화·메타정보·메모리](./docs/DATA_AND_MEMORY.md)

| 구성 컴포넌트 | 역할 |
|---|---|
| POC_V2_GATE | 공개 run/resume, Native 재진입 제어, 상태별 Tool 허용, 최종 결과 검증. |
| Native Supervisor | 저장된 제어 정보의 Agent/Task/request_id를 이용해 Worker에 위임. |
| Standard Worker | 한글/영문/동의어 해소, 실제 상품 후보 확인. |
| Query Worker | 요구 해석, SQL 생성, 승인 SQL 실행, 검토 완료 보고서 작성. |
| Review Worker | SQL 실행 전 의미·구조 검토, 실행 후 행 형태·고유 키 검토. |
| POC_V2_API | Worker가 호출하는 실제 PL/SQL 업무 처리 엔진. |
| POC_V2_RUNS / EXECS | 요청의 영속 상태와 Native 호출별 추적 이력. |
| POC_STANDARD / POC_PRODUCT_RESOLVE | 기존 표준화·실제 상품 해소 인터페이스 재사용. |

Task는 일반 3개와 Human 전용 2개다. Human Task가 추가되어도 Worker 종류는 3개다. Native Team은 sequential이며 Gate가 저장 상태를 읽어 단계별 Native 호출을 이어 간다.

## 실행 방법

기존 재사용 객체가 준비된 계정에서 이 폴더를 작업 디렉터리로 설정한 SQL*Plus를 사용한다. 접속 암호는 실행 도구에서 입력하며 저장소에 기록하지 않는다.

~~~sql
-- 최초 설치에만 실행한다. 설치 후 Team은 DISABLED다.
@install.sql
SELECT name, type, line, position, text FROM user_errors
 WHERE name LIKE 'POC_V2%' ORDER BY name, sequence;

-- 검토 후 활성화한다.
EXEC DBMS_CLOUD_AI_AGENT.ENABLE_TEAM(team_name => 'POC_V2_TEAM');

SET LONG 200000
SET LONGCHUNKSIZE 200000
SELECT POC_V2_GATE.run(
 '프로 메이플 배트의 상품 ID와 상품명과 정가를 조회해줘.',
 'ai-session-001', 'turn-001'
) AS response FROM dual;
~~~

성공 응답은 JSON의 **status=succeeded**, **report**, 실행형이면 **result.rows**를 가진다. 후보 확인은 **needs_human**과 실제 후보를 반환한다. 같은 turn 재전송에는 같은 ID를, 새로운 질문에는 새로운 turn ID를 부여한다. 원시 SELECT AI AGENT 출력은 진단용이며 최종 사용자 응답 경로는 **POC_V2_GATE.run/resume**이다.

준비 객체·권한·Ollama 설정, 후보 선택 재개, Node 클라이언트, 장애 확인은 [실행 가이드](./docs/RUNBOOK.md)를 따른다. 각 SQL과 패키지 함수 설명은 [Oracle AI Agent 프로그램](./docs/PROGRAMS.md)에 있다.

## 사용자 질문 예시 5개

| 번호 | 질문 | 의도·검증 상태 |
|---|---|---|
| 1 | 프로 메이플 배트의 상품 ID와 상품명과 정가를 조회해줘. | 실제 Native 통과. 상품 ID 129, 정가 192.99. |
| 2 | 미합중국 여자 고객이 구매한 야구용품의 매상 합계를 조회해줘. | 실제 Native 통과. 합계 6,063,776.96. |
| 3 | Team shirt의 상품 ID와 상품명과 정가를 조회해줘. | 복수 후보 확인 후 실제 후보 ID 선택·재개 API 통과. 상위 Team Human 상태 전파는 미해결. |
| 4 | 미합중국 여자 고객이 구매한 야구용품의 매상 합계 SQL만 작성해줘. 실행하지 말아줘. | SHOWSQL 의도. 전체 Native 완료 시험은 세션 중단으로 미완료. |
| 5 | 미합중국 여자 고객이 구매한 야구용품의 매상 합계 SQL을 설명해줘. 실행하지 말아줘. | EXPLAINSQL 의도 예시. 이번 v2 전체 Native 회귀 미실시. |

예시 4·5는 지원 의도를 설명하는 입력이며 통과한 결과로 제시하지 않는다. 실제 호출 예는 [05_examples.sql](./05_examples.sql)을 참고한다.

## 검증 결과와 제약

보호 검사 **20/20**, 상품 조회·판매 집계의 독립 SQL 비교, 실제 후보 선택 후 재개, 클라이언트 취소 시험이 통과했다. 표준화·메타데이터 13개 테이블의 내용 해시와 건수도 유지됐다.

Human Worker의 WAITING_FOR_HUMAN은 관찰했지만 상위 Team은 SUCCEEDED를 반환했다. 엄격한 상위 상태 검사는 **실패**로 기록한다. Gate는 영속 상태 NEEDS_CLARIFICATION을 기준으로 SQL을 차단한다. 실제 사람이 UI로 응답하는 종단 시험과 SHOWSQL/NARRATE/EXPLAINSQL 전체 Native 회귀는 완료하지 않았다. 이 저장소는 검증 범위를 명시한 POC이며 운영 적용 전 남은 연동·성능 검증이 필요하다.

[상세 검증 결과](./docs/VALIDATION.md) · [공개 검증 요약 JSON](./tests/results/summary.json)

## 문서·소스 안내

| 경로 | 내용 |
|---|---|
| docs/ARCHITECTURE.md | Native 구성, 상태 전이, 자연어 답변 처리 흐름. |
| docs/DATA_AND_MEMORY.md | 원천 데이터, 표준화/메타 테이블, 영속·대화 메모리의 차이. |
| docs/RUNBOOK.md | 전제조건, 설치·활성화·호출·확인 방법. |
| docs/PROGRAMS.md | 각 SQL 및 주요 PL/SQL 함수와 Oracle Agent API 설명. |
| docs/VALIDATION.md | 실제 시험 결과, 미완료/실패 구분, 독립 비교 SQL. |
| diagrams/*.svg | GitHub에서 열 수 있는 구조도·데이터 관계도 원본. |
| *.sql | 주석을 포함한 v2 설치·업무 처리·Agent 정의·실행 예제. |
| client.cjs, tests/ | 자격 증명을 표준입력으로 받는 실행·시험 클라이언트. |

[상위 Select AI Agent 문서](../README.md)
