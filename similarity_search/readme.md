# Oracle AI Vector Search 유사도 검색 및 RAG 실습

Oracle AI Database의 벡터 기능으로 **문서·이미지를 검색하고, 검색 결과를 LLM의 답변 근거로 활용**하는 실습 자료입니다. 키워드와 벡터 검색을 결합하는 Hybrid 예제도 포함합니다.

원본 Jupyter Notebook 6개를 Markdown 문서로 전환하고, 실행에 필요한 공통 Python 함수를 별도 모듈로 정리했습니다. SQL·Python 코드와 단계별 설명은 각 문서에서 확인합니다. Jupyter는 선택 사항이며, Markdown 자체가 실행 파일은 아닙니다.

## 문서와 권장 순서

| 순서 | 문서 | 주요 내용 |
| --- | --- | --- |
| 0 | [공통 환경과 데이터 준비](00.Setup.md) | PDB·권한·모델·원본 파일, Python과 DB의 경로 구분, Ollama 연결과 재실행 안내 |
| 1-1 | [문서 유사도 검색](1-1.simsearch_doc.md) | BLOB → 텍스트 추출 → 청킹 → 임베딩 → 벡터 저장·검색 |
| 1-2 | [이미지–이미지·텍스트–이미지 검색](1-2.smsearch_image.md) | CLIP 이미지·텍스트 인코더를 이용한 공통 공간 검색 |
| 2-1 | [문서 RAG](2-1.RAG_DOC.md) | LLM 직접 질의와 문서 CONTEXT를 추가한 응답 비교, LangChain·DB REST 경로 |
| 2-2 | [테이블 행 RAG](2-2.RAG_Table.md) | 보도제목 임베딩으로 가까운 행을 찾고 메타데이터를 근거로 응답 |
| 3 | [하이브리드 검색](3.Hybrid_search.md) | Oracle Text 키워드 검색과 벡터 검색 결합, 벡터 전용 검색과 비교 |
| 참고 | [공통 함수 설명](user_functions.md) · [Python 모듈](user_functions.py) | DB 연결·조회·DML·LOB 처리·표와 이미지 출력 |

처음에는 공통 준비 후 **문서 유사도 검색 → 문서 RAG**로 진행합니다. 이미지 검색과 테이블 RAG는 목적에 따라 선택할 수 있습니다. Hybrid는 문서 검색을 확인한 뒤 진행하며 별도 하이브리드 인덱스를 준비합니다.

## 실습 전 준비 사항

| 구분 | 준비할 내용 |
| --- | --- |
| Oracle AI Database | 온프레미스 26ai의 실습 PDB와 계정을 준비합니다. 사용 RU의 VECTOR·ONNX·HNSW·Hybrid 지원과 패키지 구성을 확인합니다. |
| Python | `oracledb`, `pandas`를 기본으로 준비하고, 이미지 실습에는 Pillow·Matplotlib, RAG에는 LangChain·Ollama 연동 패키지를 추가합니다. |
| 임베딩 모델 | 문서·테이블용 `MULTILINGUAL_E5_SMALL`, 이미지용 CLIP 이미지·텍스트 모델을 DB에 적재합니다. 모델 파일은 저장소에 포함되어 있지 않습니다. |
| 샘플 데이터 | [data](data)의 PDF·HWPX·이미지를 DB 서버에 준비하고 [데이터 준비 SQL](similarity_search_config.sql)의 필요한 구간을 계정 역할에 맞게 실행합니다. |
| LLM — RAG 선택 시 | Ollama 서비스와 생성 모델을 준비합니다. LangChain은 Python에서, DB REST는 DB 서버에서 호출하므로 각각 연결을 확인합니다. |
| 실행 위치 | Python 작업 디렉터리를 `similarity_search`로 두고 같은 문서의 코드 블록을 순서대로 실행합니다. SQL은 별도 SQL 클라이언트에서 실행합니다. |

설치·권한·파일 적재·점검 SQL은 [공통 준비 문서](00.Setup.md)에 모았습니다. DB 관리자 작업과 실습 계정 작업을 구분하며, 원본 자료 적재가 끝나기 전에 검색 예제부터 실행하지 않습니다.

## 데이터와 객체 구성

| 실습 | 원본·입력 | DB 객체 |
| --- | --- | --- |
| 문서 검색 | `data/doc`의 PDF·HWPX | `DOC_STORE`, `DOC_STORE_CHUNKS` |
| 이미지 검색 | `data/images`, 입력 이미지 `data/images/val_data` | `IMG_TBL` |
| 문서 RAG | `data/doc/rag`의 PDF | `RAG_TBL`, `RAG_TBL_V` |
| 테이블 RAG | SQL 파일의 보도자료 제목·부처·일자 | `BROAD_TBL` |
| Hybrid | `DOC_STORE` 원본 문서 | `DOC_HB_IDX1` 하이브리드 인덱스, 비교용 `DOC_STORE_CHUNKS` |

DB 서버의 DIRECTORY 경로와 Python의 상대 경로는 서로 다릅니다. HWPX 등 문서 형식은 환경의 텍스트 필터에서 실제 추출되는지 확인합니다. 이미지 예제의 `images` 폴더는 **원본 노트북의 출력 화면**이며 입력 데이터는 `data/images`에 있습니다.

## 실습에서 비교할 내용

- **검색과 생성**: 유사도 검색은 가까운 청크·행·이미지를 반환하고, RAG는 그 결과를 CONTEXT로 전달해 응답을 생성합니다.
- **문서와 테이블 RAG**: 문서 RAG는 본문 청크를, 테이블 RAG는 보도제목으로 찾은 행의 메타데이터를 사용합니다. 테이블 컬럼 정의를 임베딩하는 예제는 아닙니다.
- **정확 검색과 근사 검색**: `FETCH FIRST` 결과를 기준으로 근사 검색과 비교합니다. 인덱스를 생성했다고 모든 검색이 근사 검색으로 바뀌지는 않습니다.
- **벡터와 Hybrid**: 의미상 가까운 자료를 찾는 방식과 특정 키워드를 함께 활용하는 방식의 후보·순위 차이를 확인합니다.

## 결과 확인과 참고 문서

검색 결과는 문서번호·청크ID·이미지·원본 행에 대조합니다. RAG 답변은 실제 검색 근거에 없는 사실을 추가하지 않았는지 확인합니다. 원본 노트북의 오래된 실행 시간과 응답을 현재 성능·정답으로 고정하지 않았으며, 이미지 출력 5개만 과거 실행 예시로 보존했습니다.

- [Oracle AI Vector Search 사용자 가이드](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/index.html)
- [Oracle 문서 추출·청킹·임베딩](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/convert-file-text-chunks-embeddings-oracle-ai-database.html)
- [Oracle Hybrid SEARCH](https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/search.html)
- [python-oracledb VECTOR 지원](https://python-oracledb.readthedocs.io/en/latest/user_guide/vector_data_type.html)

문서 전환과 코드 정적 검토 기준일은 2026-11-11입니다. 실제 DB·ONNX 모델·Ollama에 연결한 실행 검증은 수행하지 않았습니다.

[상위 문서: 저장소 소개](../README.md) · [Select AI 실습](../SelectAI/README.md)
