> 로컬 원본의 한국어 분석기·vectorizer 확장 구성 예제입니다. 먼저 [공통 준비](00.Setup.md)와 [하이브리드 검색 실습](3.Hybrid_search.md)을 확인하고, 사용 RU에 맞춰 필요한 구간만 실행합니다.

## 오라클 벡터 하이브리드 검색(hybrid indexing) 사용 방법

벡터 하이브리드 쿼리는 AI 벡터검색과 키워드검색을 통합한 검색 방법으로서 벡터 검색의 정확도를 향상시키기 위한 검색 방법임. oracle26ai 이후 버전에서 지원됨.


### 사용 환경

- 23.26 버전 이후에서 사용 가능.
- CLOB, VARCHAR2, BLOB 컬럼 데이터의 검색을 지원.
- 현재, 임베딩 모델은 인디비 ONNX 모델만 사용 가능.
- HAMMING, JACCARD 디스턴스 매트릭스는 미지원.
- Mview 기반 벡터 유틸리티는 미지원.

### 벡터 하이브리드 검색을 위한 준비 및 실행

1.  SGA에 vector pool 반드시 사용

```sql

ALTER SYSTEM SET vector_memory_size = 1G SCOPE=SPFILE;

-- DBA가 메모리와 적용 범위를 확인한 뒤 필요한 경우 인스턴스 재시작

```

2. Oracle Text 실행 권한 부여

Oracle Text 사용 세부 내용은 github 참조 : https://github.com/kairkowy/Oracle-Text/blob/master/Oracle_text_hol_script_v2.md

sqlplus / as sysdba
```sql
alter session set container=freepdb1;
show user

GRANT CTXAPP TO labadmin;
GRANT EXECUTE ON CTXSYS.CTX_CLS TO labadmin;
GRANT EXECUTE ON CTXSYS.CTX_DDL TO labadmin;
GRANT EXECUTE ON CTXSYS.CTX_DOC TO labadmin;
GRANT EXECUTE ON CTXSYS.CTX_OUTPUT TO labadmin;
GRANT EXECUTE ON CTXSYS.CTX_QUERY TO labadmin;
GRANT EXECUTE ON CTXSYS.CTX_REPORT TO labadmin;
GRANT EXECUTE ON CTXSYS.CTX_THES TO labadmin;
GRANT EXECUTE ON CTXSYS.CTX_ULEXER TO labadmin;
```

3. Text index의 preference생성

sqlplus vector/vector@freepdb1

```sql

exec ctx_ddl.create_preference('KO_LEXER', 'KOREAN_MORPH_LEXER');
exec ctx_ddl.set_attribute('KO_LEXER','COMPOSITE','NGRAM');
exec ctx_ddl.create_preference('DOC_FILTER', 'AUTO_FILTER');

```

4. 임베딩 preference 생성


```sql
begin
  DBMS_VECTOR_CHAIN.CREATE_PREFERENCE('vectorizer_spec',
     dbms_vector_chain.vectorizer,
        json('{
            "vector_idxtype" :  "hnsw",
            "model"          :  "labadmin.MULTILINGUAL_E5_SMALL",
            "by"             :  "words",
            "max"            :  200,
            "overlap"        :  10,
            "split"          :  "recursively",
            "language"       : "korean",
            "normalization" : "all"
         }'
        ));
end;
/
```

preference 삭제

```sql
exec DBMS_VECTOR_CHAIN.DROP_PREFERENCE('vectorizer_spec');
```

참고자료 https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/create_preference.html#GUID-B83978CD-EAF8-4794-9652-F335C54C3385


5. 하이브리드 인덱싱 생성

```sql
CREATE HYBRID VECTOR INDEX doc_hb_idx1 on
  doc_store(doc)
  parameters('VECTORIZER vectorizer_spec
              DATASTORE CTXSYS.DEFAULT_DATASTORE
              LEXER ko_lexer
              FILTER doc_filter')
;
```

6. 벡터 하이브리드 쿼리

``` sql
select json_Serialize(
  dbms_hybrid_vector.search(
    json('{ "hybrid_index_name"     : "doc_hb_idx1",
            "vector":
                    { "search_text" : "고향사랑 기부 상반기 모금 결과",
                      "search_mode" : "CHUNK"},
            "text"  :
                    { "contains"    : "고향사랑기부금법"},
            "return":
                    { "topN"        : 3 }
          }'
          )
  ) pretty) as result
from dual;        // chunk 모드

RESULT
--------------------------------------------------------------------------------
[
  {
    "rowid" : "AAASFcAAAAAAAR7AAI",
    "score" : 85.97,
    "vector_score" : 93.87,
    "text_score" : 7,
    "vector_rank" : 1,
    "text_rank" : 1,
    "chunk_text" : "고향사랑기부 상반기 모금 실적 주요 분석 결과는 다음과 같다.\
n\n○ 월별로는 3월(약 98.2억 원, 약 8만 6천 건), 4월(약 85.9억 원, 약 6만\n\n4천
건)에 전체 모금의 50% 이상이 집중됐다. 이는 지난 3월경 발생한\n\n산불 피해 극복
을 위한 대국민 기부\n\n*\n\n가 영향을 미친 것으로 보인다.",
    "chunk_id" : "6"
  },
  {
    "rowid" : "AAASFcAAAAAAAR7AAI",
    "score" : 85.95,
    "vector_score" : 93.84,
    "text_score" : 7,
    "vector_rank" : 2,
    "text_rank" : 1,
    "chunk_text" : "해당하는 수준으로, 통상적으로 연말에 기부가 집중되는 점을 고
려할 때\n\n예년 모금액을 크게 넘어설 것으로 전망된다.\n\n- 2 -\n\n〈 연도별 상반
기 모금액 추이 〉\n\n(억 원)\n\n〈 연도별 상반기 모금건수 추이 〉\n\n(만 건)\n\n
'23.상\n\n'24.상\n\n'25.상\n\n'23.상\n\n'24.상\n\n'25.상\n\n□ 올해 고향사랑기부
상반기 모금 실적 주요 분석 결과는 다음과 같다.",
    "chunk_id" : "5"
  },
  {
    "rowid" : "AAASFcAAAAAAAR7AAI",
    "score" : 85.45,
    "vector_score" : 93.3,
    "text_score" : 7,
    "vector_rank" : 3,
    "text_rank" : 1,
    "chunk_text" : "이후 누적 모금액 100억 원 돌파, 성공적으로 안착\n\n- 오프라
인 답례품 원스톱 신청 절차 개시, 민간플랫폼 확대 지속 추진 예정\n\n□ 행정안전부
는 2025년 고향사랑기부 상반기 모금 결과, 모금액과 모금\n\n건수가 지난 2년 같은
기간과 비교했을 때 각각 큰 폭으로 증가했다고\n\n밝혔다.\n\n○ 2025년 상반기 고향
사랑기부 총 모금액은 약 348억 8천만 원, 총 모금\n\n건수는 약 27만 9천 건이다.\n\
n※",
    "chunk_id" : "2"
  }
]

SELECT json_Serialize(
DBMS_HYBRID_VECTOR.SEARCH(
    json(
      '{ "hybrid_index_name" : "doc_hb_idx1",
         "search_text"       : "고향사랑 기부 상반기 모금 결과",
         "search_scorer"     : "rsf",
         "return" : {"topN" : 2}
      }')
    ) pretty) as result
FROM DUAL;      // Document 모드

RESULT
--------------------------------------------------------------------------------
[
  {
    "rowid" : "AAASFcAAAAAAAR7AAI",
    "score" : 91.79,
    "vector_score" : 93.87,
    "text_score" : 71,
    "vector_rank" : 1,
    "text_rank" : 1,
    "chunk_text" : "고향사랑기부 상반기 모금 실적 주요 분석 결과는 다음과 같다.\
n\n○ 월별로는 3월(약 98.2억 원, 약 8만 6천 건), 4월(약 85.9억 원, 약 6만\n\n4천
건)에 전체 모금의 50% 이상이 집중됐다. 이는 지난 3월경 발생한\n\n산불 피해 극복
을 위한 대국민 기부\n\n*\n\n가 영향을 미친 것으로 보인다. == 해당하는 수준으로,
통상적으로 연말에 기부가 집중되는 점을 고려할 때\n\n예년 모금액을 크게 넘어설 것
으로 전망된다.\n\n- 2 -\n\n〈 연도별 상반기 모금액 추이 〉\n\n(억 원)\n\n〈 연도
별 상반기 모금건수 추이 〉\n\n(만 건)\n\n'23.상\n\n'24.상\n\n'25.상\n\n'23.상\n\
n'24.상\n\n'25.상\n\n□ 올해 고향사랑기부 상반기 모금 실적 주요 분석 결과는 다음
과 같다. == 이후 누적 모금액 100억 원 돌파, 성공적으로 안착\n\n- 오프라인 답례품
 원스톱 신청 절차 개시, 민간플랫폼 확대 지속 추진 예정\n\n□ 행정안전부는 2025년
고향사랑기부 상반기 모금 결과, 모금액과 모금\n\n건수가 지난 2년 같은 기간과 비교
했을 때 각각 큰 폭으로 증가했다고\n\n밝혔다.\n\n○ 2025년 상반기 고향사랑기부 총
모금액은 약 348억 8천만 원, 총 모금\n\n건수는 약 27만 9천 건이다.\n\n※ == - 1 -\
n\n보도자료\n\n보도시점\n\n(온라인)\n\n2025. 7. 16.(수) 12:00\n\n(지 면)\n\n2025
. 7. 17.(목) 조간\n\n고향사랑기부로 불어넣은 지역활력,\n\n2025년 상반기 모금결과
 공개\n\n- 상반기 총 모금액 349억 원(전년대비 1.7배), 총 모금건수 28만 건(전년대
비 1.9배)\n\n- 지정기부 시행(2024년 6월) 이후 누적 모금액 100억 원 돌파, 성공적
으로 안착 == '23년\n\n1,371건 →\n\n'24년\n\n730건 →\n\n'25년\n\n775건\n\n○ 한편,
 올해부터 기부 한도가 500만 원에서 2,000만 원으로 상향되었다.\n\n이에, 500만 원
초과 2,000만 원 미만 기부는 144건이었으며, 2,000만 원\n\n기부는 총 39건으로 제도
 개선 이후 고액 기부자의 수요가 기부에\n\n반영된 것으로 나타났다.\n\n□ 모금실적
증가와 함께 지방자치단체 답례품 판매액(약 91억 8천만 원)\n\n역시 전년 대비 약 17
3%에 해당하는 수준을 달성해, 고향사랑기부가 == 건수는 약 27만 9천 건이다.\n\n※\n
\n온라인(약 297억 원, 약 25만 7천 건) / 오프라인(약 51억 8천만 원, 약 2만 2천 건
)\n\n○ 올해로 시행 3년 차를 맞이하는 고향사랑기부제는 지난 두 해 동안의\n\n모금
실적을 모두 앞질러, 같은 기간 2023년 대비 약 1.5배, 2024년 대비\n\n약 1.7배 수준
의 모금액을 달성했다.\n\n※ == 진입해, 해당 지방자치단체의 재난피해 극복과 지역경
제 활성화에 고향\n\n사랑기부가 기여한 것으로 나타났다.\n\n□\n\n｢\n\n고향사랑기부
금법\n\n｣\n\n개정(2024.2.20.)으로 지난해 6월 4일에 공식 시행된\n\n지정기부의 누
적 모금액은 시행 1년여 동안 약 123억 원을 달성하며,\n\n제도가 성공적으로 안착하
고 있는 것으로 분석됐다.\n\n* 2025년 상반기 동안 123개 사업 모금을 진행, 이 중 2
2개 사업은 모금 완료\n\n○ 전북특별자치도 고창군은 '고창 청소년 앞날창창 프로그램
' 지정기부 사업\n\n모금을 진행해, 모금액(총 6천만 원)을 장학재단에 전달하고 사회
적 == ...(1)",
    "chunk_id" : "1; 2; 3; 5; 6; 8; 10; 12"
  },

```

참고자료 https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/search.html


7. SEARCHPIPELINE 샘플

```sql

SELECT jt.*
FROM JSON_TABLE(
       json_serialize(
         dbms_hybrid_vector.search(
           json('{
             "hybrid_index_name" : "doc_hb_idx1",
             "vector" : {
               "search_text" : "고향사랑 기부 상반기 모금 결과",
               "search_mode" : "CHUNK"
             },
             "text" : {
               "contains" : "고향사랑기부금법"
             },
             "return" : {
               "topN" : 2
             }
           }')
         )
         RETURNING CLOB
       ),
       '$[*]'
       COLUMNS
         idx          FOR ORDINALITY,
         doc_rowid    VARCHAR2(30)    PATH '$.rowid',
         score        NUMBER          PATH '$.score',
         vector_score NUMBER          PATH '$.vector_score',
         text_score   NUMBER          PATH '$.text_score',
         vector_rank  NUMBER          PATH '$.vector_rank',
         text_rank    NUMBER          PATH '$.text_rank',
         chunk_text   CLOB            PATH '$.chunk_text',
         chunk_id     VARCHAR2(100)   PATH '$.chunk_id',
         paths        CLOB FORMAT JSON PATH '$.paths'
     ) jt
ORDER BY jt.idx;

       IDX DOC_ROWID                           SCORE VECTOR_SCORE TEXT_SCORE VECTOR_RANK  TEXT_RANK
---------- ------------------------------ ---------- ------------ ---------- ----------- ----------
CHUNK_TEXT                                                                       CHUNK_ID
-------------------------------------------------------------------------------- ------------------------------
PATHS
--------------------------------------------------------------------------------
         1 AAASFcAAAAAAAR7AAI                  85.97        93.87          7           1          1
고향사랑기부 상반기 모금 실적 주요 분석 결과는 다음과 같                         6


         2 AAASFcAAAAAAAR7AAI                  85.95        93.84          7           2          1
해당하는 수준으로, 통상적으로 연말에 기부가 집중되는 점                          5


```
