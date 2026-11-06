# SELECT AI 소개 및 실습

Select AI의 기본 개념과 Ollama 기반 실습환경을 살펴보고, Annotation 적용 전후의 SQL 생성 정확도를 비교하는 자료입니다. 다음 순서로 진행합니다.

| 순서 | 문서 | 주요 내용 |
|---|---|---|
| 1 | [SELECT AI 소개](SelectAi_Intro.md) | 개념, 구조, 처리 흐름, 실행 방법, Action과 프로파일 주요 속성 |
| 2 | [SELECT AI 실습환경 구성](SelectAiConfigure.md) | DBMS_CLOUD 설치, Wallet 구성, CDB·PDB ACL과 권한 설정 |
| 3 | [SELECT AI 샘플 데이터 구성](SampleDataConfig.md) | SH 스키마 구조, 전체 테이블 복사, 기본키·외래키 생성, Annotation 등록과 확인 |
| 4 | [SELECT AI 예제](SelectAiExample.md) | 단일 테이블·조인 질문, Annotation 미사용·사용 프로파일과 실행 구문 |

실습 계정은 `lab00`이며, Oracle 샘플 SH의 전체 9개 테이블을 복사하여 사용합니다. 예제 스크립트는 각 문서의 코드 블록에 포함되어 있습니다.

그림 파일: [SELECT AI 구조도(SVG)](images/select-ai-architecture.svg)
