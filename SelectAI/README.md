# Oracle Select AI 소개 및 실습

Oracle AI Database의 **Select AI**를 온프레미스 환경에서 구성하고 활용하는 실습 자료입니다. 자연어 질문을 SQL로 변환하는 NL2SQL부터 Annotation을 활용한 업무 의미 보완, 문서 검색 기반 RAG, 도구를 사용하는 AI Agent, 합성 데이터 생성(SDG)까지 살펴봅니다.

이 폴더는 **개념과 환경 준비 → 데이터 조회 → 문서 검색 → 에이전트 활용** 순서로 학습하도록 구성했습니다. SDG는 데이터 생성이 필요한 경우 선택하는 별도 실습이며, Ollama·Nginx 설정은 환경 준비 중 참고하는 보조 자료입니다.

## 폴더와 문서 안내

GitHub의 이름순 정렬에서도 학습 순서를 확인할 수 있도록 폴더명에 번호를 붙였습니다. `99`는 순서대로 수행할 마지막 실습이 아니라 필요할 때 참조하는 보조 자료를 의미합니다.

| 순서 | 폴더 | 시작 문서 | 학습 내용 |
| --- | --- | --- | --- |
| 01 | `01_SelectAI_Intro_Lab` | [Select AI 소개 및 실습](01_SelectAI_Intro_Lab/README.md) | 구조·Action·Profile, 온프레미스 환경 구성, SH 샘플 데이터, Annotation 미사용·사용 비교 |
| 02 | `02_SelectAI_RAG` | [파일시스템 기반 RAG](02_SelectAI_RAG/SelectAI_RAG.md) | 로컬 문서 위치 지정, 임베딩 모델과 Select AI 벡터 인덱스 구성, 검색·답변·출처 확인 |
| 03 | `03_SelectAI_Agent` | [Select AI Agent 소개 및 실습](03_SelectAI_Agent/README.md) | Agent·Tool·Task·Team 구성, SQL·RAG·PL/SQL 도구, HR JOIN과 통계 분석 |
| 04 | `04_SelectAI_SDG` | [합성 데이터 생성](04_SelectAI_SDG/SyntheticDataGeneration_example.md) | 대상 테이블과 생성 지침을 바탕으로 테스트 데이터 생성 |
| 99 | `99_SelectAI_ETC` | [Ollama·Nginx 프록시 구성](99_SelectAI_ETC/Ollama_Proxy_Config.md) | 로컬 LLM 연결을 위한 서비스·프록시 구성 참고 |

## 권장 학습 순서

### 1. Select AI 기본 개념과 환경 준비

[Intro README](01_SelectAI_Intro_Lab/README.md)의 순서에 따라 개념을 확인한 뒤, 관리자가 계정 생성 → 패키지·Wallet·ACL 구성 → 권한 확인을 진행합니다. 실습자는 자신의 계정으로 접속해 데이터를 복사하고 Annotation을 등록합니다.

환경이 이미 준비되어 있다면 해당 README의 준비 사항을 점검하고 예제 단계부터 진행합니다. 여러 계정으로 실습할 때는 각 계정의 ACL과 패키지 실행 권한을 확인합니다.

### 2. 자연어 데이터 조회와 Annotation 비교

[Select AI 예제](01_SelectAI_Intro_Lab/SelectAiExample.md)에서 단일 테이블 질문과 JOIN 질문을 실행합니다. Part 1의 `annotations=false`와 Part 2의 `annotations=true`에 **동일한 질문과 데이터**를 사용하고, 생성 SQL과 조회 결과를 업무 정의에 맞춰 비교합니다.

### 3. 문서 기반 RAG

[RAG 실습](02_SelectAI_RAG/SelectAI_RAG.md)에서 로컬 PDF를 검색 대상으로 지정하고 임베딩·벡터 인덱스를 구성합니다. 테이블 메타데이터를 이용하는 NL2SQL과 문서 청크를 근거로 답하는 RAG의 차이를 살펴봅니다. 문서 적재 완료와 실제 검색 내용을 확인한 뒤 최종 응답의 출처를 대조합니다.

### 4. 도구를 사용하는 AI Agent

[Agent README](03_SelectAI_Agent/README.md)와 [온프레미스 공통 환경 구성](03_SelectAI_Agent/OnPremises_Setup.md)을 확인한 뒤 SQL·RAG 기본 예제를 진행합니다. 이후 목적에 맞게 HR JOIN, PL/SQL 함수 기반 벡터 검색, 통계 분석 예제를 선택합니다.

### 5. 합성 데이터 생성 — 선택 실습

[SDG 예제](04_SelectAI_SDG/SyntheticDataGeneration_example.md)에서 대상 테이블과 생성 지침을 지정해 테스트 데이터를 생성합니다. Intro의 Profile·LLM 연결을 이해한 뒤 진행할 수 있으며, RAG나 Agent 실습을 먼저 완료할 필요는 없습니다. 생성 결과의 형식·건수·업무 규칙을 확인합니다.

## 목적에 따라 바로 찾아보기

| 목적 | 참고 문서 |
| --- | --- |
| Select AI가 어떻게 동작하는지 이해하기 | [소개·구조·처리 흐름](01_SelectAI_Intro_Lab/SelectAi_Intro.md) |
| 실습 계정과 환경을 처음 구성하기 | [Intro 실습 순서와 준비 사항](01_SelectAI_Intro_Lab/README.md) |
| 업무 용어를 SQL 조건과 JOIN에 반영하기 | [샘플 데이터와 Annotation](01_SelectAI_Intro_Lab/SampleDataConfig.md), [비교 예제](01_SelectAI_Intro_Lab/SelectAiExample.md) |
| 로컬 문서를 검색해 근거 있는 응답 만들기 | [RAG 실습](02_SelectAI_RAG/SelectAI_RAG.md) |
| 기존 벡터 테이블과 검색 함수를 도구로 연결하기 | [PL/SQL 벡터 검색 Agent](03_SelectAI_Agent/SAIAgent-plsql4vectorsearch-example.md) |
| SQL·RAG 도구로 여러 단계의 요청 처리하기 | [Agent 문서 목록](03_SelectAI_Agent/README.md) |
| 테스트 데이터 생성하기 | [SDG 예제](04_SelectAI_SDG/SyntheticDataGeneration_example.md) |

## 공식 문서와 결과 확인

[Oracle Select AI 사용자 가이드](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/index.html)와 [기능 지원표](https://docs.oracle.com/en/database/oracle/oracle-database/26/saicm/index.html)를 참고합니다. 온프레미스 패키지 설치는 [Oracle DBMS_CLOUD 설치 안내](https://docs.oracle.com/en/database/oracle/oracle-database/26/sutil/installing-dbms_cloud.html)를 기준으로 확인합니다.

각 예제는 사용 RU·모델·프롬프트·원본 데이터에 따라 결과가 달라질 수 있습니다. 생성 SQL은 원본 SQL 결과와, RAG·Agent 답변은 검색 근거와 도구 실행 이력에 대조합니다. 실제 실행 검증 여부와 개별 전제 조건은 각 문서를 확인합니다.

[상위 문서: 저장소 소개](../README.md)
