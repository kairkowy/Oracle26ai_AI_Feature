# Oracle Select AI Agent

Oracle Select AI Agent의 기본 개념과 구성 방법을 소개하고, SQL·RAG·사용자 정의 PL/SQL 도구를 활용한 실습 예제를 제공합니다. SQL과 PL/SQL을 사용해 에이전트를 구성하고, 자연어 요청으로 데이터를 조회하거나 문서를 검색하는 과정을 살펴봅니다.

## 문서 안내

| 문서 | 주요 내용 |
| --- | --- |
| [기본 개념과 아키텍처](./SelectAI%20Agent-overview.md) | ReAct 기반 동작 방식, 계층 구조, Agent·Tool·Task·Team 등 핵심 객체와 활용 시나리오 |
| [SQL·RAG 도구 기본 예제](./Oracle26ai%20SelectAI%20Agent.md) | SQL 도구를 이용한 테이블 조회, RAG 도구를 이용한 PDF 문서 검색, 실행 이력과 오류 확인 |
| [HR 데이터 조회와 JOIN 예제](./Oracle26ai%20SelectAI%20Agent-HR.md) | HR 샘플 테이블의 Annotation을 활용한 자연어 조회와 여러 테이블 간 JOIN |
| [PL/SQL 함수 기반 벡터 검색 예제](./SAIAgent-plsql4vectorsearch-example.md) | 기존 벡터 테이블을 검색하는 PL/SQL 함수를 도구로 등록하고, 검색 결과를 근거로 답변하는 에이전트 구성 |
| [통계 분석 에이전트 예제](./SAIAgent-analytic-agent-example.md) | 관광객 카드 이용 이력에 대한 SQL 기반 집계·통계 분석과 실행 결과 확인 |

## 권장 학습 순서

1. **기본 개념과 아키텍처**에서 에이전트의 동작 방식과 핵심 객체의 역할을 확인합니다.
2. **SQL·RAG 도구 기본 예제**에서 프로파일과 에이전트 객체를 생성하고 실행하는 흐름을 익힙니다.
3. 목적에 맞는 확장 예제를 선택합니다.

| 실습 목적 | 선택할 예제 |
| --- | --- |
| 여러 업무 테이블을 연결해 자연어로 조회하기 | HR 데이터 조회와 JOIN 예제 |
| 기존 벡터 테이블과 검색 함수를 재사용하기 | PL/SQL 함수 기반 벡터 검색 예제 |
| 데이터의 합계·분포·순위 등을 분석하기 | 통계 분석 에이전트 예제 |

Select AI를 처음 사용하는 경우 [Select AI 소개 및 실습](../SelectAI_Intro_Lab/README.md)에서 환경 구성과 데이터 준비를 먼저 진행합니다.

## 실습 전 준비

이 폴더의 예제는 Oracle AI Database 26ai와 Ollama 기반 LLM 연결 구성을 사용합니다. 예제별로 사용하는 모델과 데이터가 다르므로 해당 문서의 설정을 확인합니다.

| 구분 | 확인 사항 |
| --- | --- |
| 데이터베이스와 권한 | 실습 환경에서 `DBMS_CLOUD_AI`와 `DBMS_CLOUD_AI_AGENT`를 사용할 수 있는지, 실습 계정에 필요한 패키지 실행 권한과 데이터 접근 권한이 있는지 확인합니다. |
| LLM 연결 | 데이터베이스에서 Ollama 서비스에 접근할 수 있도록 네트워크와 프록시를 구성하고, 예제에서 사용할 모델을 준비합니다. [Ollama·Nginx 프록시 구성](../SelectAI_ETC/Ollama_Proxy_Config.md)을 참고합니다. |
| 실행 도구 | SQL과 PL/SQL 스크립트를 실행할 수 있는 SQL 클라이언트를 준비합니다. |

### 예제별 데이터 준비

| 예제 | 필요한 데이터·객체 |
| --- | --- |
| SQL 도구 기본 예제 | 프로파일의 `object_list`에 지정된 `TOUR_HIST_TBL_ENG`, `DOC_STORE` 테이블 |
| RAG 도구 기본 예제 | `DOC_DIR` 디렉터리 객체와 검색할 PDF 파일, `MULTILINGUAL_E5_SMALL` 임베딩 모델 |
| HR 데이터 조회와 JOIN 예제 | HR 샘플 테이블, 해당 테이블에 대한 접근 권한과 Annotation 설정 |
| PL/SQL 함수 기반 벡터 검색 예제 | 문서 내용과 벡터가 저장된 `RAG_TBL_V` 테이블, 검색에 사용할 `MULTILINGUAL_E5_SMALL` 임베딩 모델 |
| 통계 분석 에이전트 예제 | 관광객 카드 이용 이력이 저장된 `TOUR_HIST_TBL` 테이블 |

## 에이전트 구성과 실행 흐름

각 예제는 다음 객체를 구성한 뒤 팀을 실행합니다. 객체 생성 순서는 예제별 스크립트를 따릅니다.

| 객체 | 역할 |
| --- | --- |
| AI Profile | 사용할 LLM과 연결 정보를 설정합니다. SQL·RAG 도구용 프로파일에는 조회 대상 객체나 검색 관련 설정도 지정합니다. |
| Tool | SQL 조회, RAG 검색, PL/SQL 함수 호출 등 실제 작업을 수행합니다. |
| Task | 수행할 작업, 사용할 도구, 응답 지침을 정의합니다. |
| Agent | AI 프로파일과 역할을 바탕으로 작업을 수행합니다. |
| Team | Agent와 Task를 연결하고 실행 흐름을 정의합니다. |

구성 후에는 `DBMS_CLOUD_AI_AGENT.SET_TEAM`으로 세션에 팀을 지정해 `SELECT AI AGENT`로 요청하거나, `DBMS_CLOUD_AI_AGENT.RUN_TEAM`을 호출합니다. 대화형 실행과 실행 이력 조회 방법은 각 예제를 참고합니다.

## 실행 시 확인 사항

- 예제의 `provider_endpoint`, 모델명, 스키마명, 테이블명, 디렉터리명은 자신의 환경에 맞게 변경합니다.
- 예제에는 기존 프로파일·도구·작업·에이전트·팀 등을 삭제하고 다시 생성하는 구문이 포함되어 있습니다. 실행 전에 대상 객체명을 확인합니다.
- 문서에 수록된 응답은 실행 결과의 예시입니다. 사용한 모델, 프롬프트, 데이터에 따라 결과가 달라질 수 있으므로 실제 조회 결과와 검색 근거를 함께 확인합니다.

---

[상위 문서: Select AI](../README.md)
