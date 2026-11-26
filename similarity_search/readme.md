# Oracle AI Vector Search 유사도 검색 및 RAG 실습

Oracle AI Database의 문서·이미지 유사도 검색, 문서·테이블 RAG, 하이브리드 검색 실습입니다. Notebook 기반 Python 코드로 실행하며, 같은 내용의 Markdown 문서에서 Python 코드와 준비 SQL을 확인할 수 있습니다.

## Jupyter Notebook

처음 서버를 구성한다면 [Oracle Linux 9 Notebook 환경 구성 가이드](notebook/README.md)를 먼저 진행합니다. `lab` 계정의 Python 가상환경·JupyterLab 설치부터 SSH 터널 접속, DB·Ollama 점검까지 순서대로 설명합니다.

Markdown 문서와 같은 이름의 노트북 6개를 복원했습니다. Python 작업 디렉터리를 `similarity_search`로 두고 실행합니다. 공통 함수는 `user_functions.py`를 사용합니다.

- [문서 유사도 검색](1-1.simsearch_doc.ipynb)
- [이미지 유사도 검색](1-2.smsearch_image.ipynb)
- [문서 RAG](2-1.RAG_DOC.ipynb)
- [테이블 RAG](2-2.RAG_Table.ipynb)
- [하이브리드 검색](3.Hybrid_search.ipynb)
- [공통 함수 설명과 코드](user_functions.ipynb)

## 실습 순서와 문서

| 순서 | 문서 | 포함 내용 |
| --- | --- | --- |
| 0 | [공통 환경과 데이터 준비](00.Setup.md) | 실행 위치, 패키지, 권한·모델, 파일 경로, 연결 확인 |
| 1-1 | [문서 유사도 검색](1-1.simsearch_doc.md) | DOC_STORE·청크 테이블 생성과 전체 문서 적재 SQL, 임베딩·검색 Python |
| 1-2 | [이미지 유사도 검색](1-2.smsearch_image.md) | IMG_TBL 생성과 전체 이미지 적재 SQL, CLIP 이미지·텍스트 검색 |
| 2-1 | [문서 RAG](2-1.RAG_DOC.md) | RAG 테이블 생성·PDF 적재 SQL, LangChain·DB REST 호출 |
| 2-2 | [테이블 RAG](2-2.RAG_Table.md) | BROAD_TBL 생성과 전체 보도자료 INSERT, 행 검색 기반 응답 |
| 3 | [하이브리드 검색](3.Hybrid_search.md) | 하이브리드 인덱스 SQL, 키워드·벡터 검색 및 결과 비교 |
| 참고 | [공통 Python 함수](user_functions.md) | 함수 설명과 전체 Python 코드, 실행 모듈 [user_functions.py](user_functions.py) |

공통 준비 후 문서 검색 → 문서 RAG 순서로 진행합니다. 이미지 검색·테이블 RAG는 독립적으로 선택할 수 있으며, Hybrid는 문서 데이터 적재 후 진행합니다.

## 코드 실행 방법

1. [data](data)의 원본 문서·이미지를 DB 서버에 준비하고 필요한 ONNX 모델을 적재합니다. 모델 파일은 별도로 준비합니다.
2. 각 문서의 **테이블 생성과 샘플 데이터 적재 SQL**을 관리자 작업과 실습 계정 작업으로 나누어 실행합니다. DB 경로는 실제 환경에 맞게 변경합니다.
3. Python 작업 디렉터리를 `similarity_search`로 두고 같은 문서의 Python 코드 블록을 위에서 아래로 같은 세션에서 실행합니다. 공통 함수는 `user_functions.py`에서 가져옵니다.
4. RAG는 Ollama 서비스·생성 모델과 Python 및 DB 서버의 연결을 각각 준비합니다.

Markdown 코드 블록은 화면에서 자동 실행되지 않습니다. `sql` 블록은 SQL*Plus·SQLcl 등 SQL 클라이언트에서, `python` 블록은 Python에서 실행합니다. Python 문자열에 들어 있는 검색·임베딩 SQL은 해당 Python 코드가 바인드 값과 함께 실행합니다.

접속 정보는 `ORACLE_USER`, `ORACLE_PASSWORD`, `ORACLE_DSN` 환경 변수 또는 입력을 사용합니다. 기존 객체가 있는 경우 전체 준비 SQL을 반복 실행하지 말고 필요한 단계를 선택합니다.

## 추가 환경 가이드

- [Oracle·Ollama 환경 구성](오라클%20-%20Ollama%20환경%20RAG%20예제%20시나리오%20준비.md): 로컬 원본의 23ai 환경 구성 기록과 추가 SQL 예제입니다.
- [한국어 하이브리드 인덱싱 상세](오라클%20벡터%20hybrid%20indexing%20사용%20방법.md): 한국어 lexer·vectorizer preference와 검색 SQL입니다.
- [여러 사용자 실습 계정](multi_user_config.md): Linux 계정 생성 셸 코드와 Oracle DB 계정 정리 SQL입니다.

## 데이터와 검증 범위

`data/doc`는 일반 문서, `data/doc/rag`는 RAG용 PDF, `data/images`는 검색 대상 이미지, `data/images/val_data`는 입력용 이미지입니다. `images`는 과거 실행 결과 이미지입니다.

준비 SQL은 각 실습 문서에 통합되어 있습니다. 자동 백업과 Windows 바로가기는 제외합니다. 원본 폴더에는 바로가기 대상인 Ollama 오프라인 설치 문서 본문이 없습니다.

문서 반영 기준일은 2026-11-26입니다. 코드 보존·파일 참조·문서 링크를 정적으로 검토했으며, 실제 DB·ONNX 모델·Ollama에 연결한 실행 검증은 수행하지 않았습니다.

[상위 문서](../README.md) · [Select AI 실습](../SelectAI/README.md)
