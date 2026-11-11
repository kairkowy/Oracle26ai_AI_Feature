### Select AI RAG


#### 2. 파일시스템 스토어 기반 SELECTAI RAG

1. 파일시스템 스토어 생성

```sql
create or replace directory doc_dir as '/home/oracle/labs/data/docs/rag';

```

2. SELECTAI RAG 프로파일 및 벡터인덱싱

```sql

BEGIN
  BEGIN
    DBMS_CLOUD_AI.DROP_PROFILE('SAI_RAG_FSSTORE_PROFILE', force => TRUE);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'SAI_RAG_FSSTORE_PROFILE',
    attributes   => '{
      "provider_endpoint": "http://service-ollama/v1",
      "model": "qwen2.5-coder:7b",
      "conversation": false,
      "temperature": 0.1,
      "max_tokens": 1024,
      "vector_index_name":"SAI_RAG_IDX",
      "embedding_model": "database:MULTILINGUAL_E5_SMALL"
    }',
    status => 'enabled'
  );
END;
/

EXEC DBMS_CLOUD_AI.SET_PROFILE('SAI_RAG_FSSTORE_PROFILE');

BEGIN
  -- 기존 인덱스 있으면 삭제
  BEGIN
    DBMS_CLOUD_AI.DROP_VECTOR_INDEX(
      index_name   => 'SAI_RAG_IDX',
      include_data => TRUE,
      force        => TRUE
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  -- 벡터 인덱스 생성
  DBMS_CLOUD_AI.CREATE_VECTOR_INDEX(
    index_name => 'SAI_RAG_IDX',
    attributes        => '{
          "vector_db_provider": "oracle",
          "location": "DOC_DIR:*.pdf",
          "profile_name": "SAI_RAG_FSSTORE_PROFILE",
          "vector_dimension": 384,
          "vector_distance_metric": "cosine",
          "chunk_size":500,
          "chunk_overlap":50
        }'
  );
END;
/


EXEC DBMS_CLOUD_AI.CLEAR_PROFILE;
EXEC DBMS_CLOUD_AI.SET_PROFILE('SAI_RAG_FSSTORE_PROFILE');

col data format a50
col source format a30
col url format a50

SELECT AI SHOWSQL 공공기관 소프트웨어 분리발주 대상 사업에는 어떤 것들이 있나요?;


SELECT AI RUNSQL 공공기관 소프트웨어 분리발주 대상 사업에는 어떤 것들이 있나요?;

DATA                                                                                                 SOURCE                   URL                                              SCORE
---------------------------------------------------------------------------------------------------- ------------------------------ -------------------------------------------------- ----------
START_OFFSET END_OFFSET
------------ ----------
0호)」전부를 개정하고, 다음과 같이 고시합니다.                                                       software_order.pdf             "DOC_DIR":software_order.pdf                              .92



2015년 12
       72451      72950

 이상인 사업을 분리발주 대상 사업으로 한다.                                                          software_order.pdf             "DOC_DIR":software_order.pdf                              .92


DATA                                                                                                 SOURCE                   URL                                              SCORE
---------------------------------------------------------------------------------------------------- ------------------------------ -------------------------------------------------- ----------
START_OFFSET END_OFFSET
------------ ----------


②



제1항
       72901      73400


DATA                                                                                                 SOURCE                   URL                                              SCORE
---------------------------------------------------------------------------------------------------- ------------------------------ -------------------------------------------------- ----------
START_OFFSET END_OFFSET
------------ ----------
대상 소프트웨어)                                                                                     software_order.pdf             "DOC_DIR":software_order.pdf                              .92



①�분리발주�대상�소프트웨어는�
        4501       5000

                                                                                                     software_order.pdf       "DOC_DIR":software_order.pdf                       .91


DATA                                                                                                 SOURCE                   URL                                              SCORE
---------------------------------------------------------------------------------------------------- ------------------------------ -------------------------------------------------- ----------
START_OFFSET END_OFFSET
------------ ----------


관계없음



2.1 사용되는 상용 소프트웨어의 가격이 5천
       69751      70250


DATA                                                                                                 SOURCE                   URL                                              SCORE
---------------------------------------------------------------------------------------------------- ------------------------------ -------------------------------------------------- ----------
START_OFFSET END_OFFSET
------------ ----------
은�법�시행령�제9조의3제1항에�따라�조달청장에게�                                                      software_order.pdf             "DOC_DIR":software_order.pdf                              .91
        5401       5900

SELECT AI NARRATE 공공기관 소프트웨어 분리발주 대상 사업에는 어떤 것들이 있나요?;

RESPONSE
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
공공기관이 소프트웨어를 분리발주하는 대상 사업은 다음과 같습니다:

1. 총 사업 규모가 5억원 이상인 소프트웨어 사업

2. 가격이 5천만원 이상이며, 다음 각 호 중 하나에 해당하는 소프트웨어:
   - 전자조달의 이용 및촉진에 관한 법률 제2조에 따라 국가종합전자조달시스템 종합쇼핑몰 등록 소프트웨어 제품
   - 소프트웨어산업 진흥법 제13조에 따라 소프트웨어품질 인증 제품(Good Software)
   - 정보보호시스템(CC) 인증 소프트웨어 제품 및 전자정부법 제56조에 따라 국가보원 검증 또는 지정 소프트웨어 제품
   - 산업기술혁신촉진법 제16조에 따라 신제품(NEP) 인증 소프트웨어 제품
   - 산업기술혁신촉진법 제15조의2에 따라 신기술(NET) 인증 소프트웨어 제품

Sources:
  - software_order.pdf ("DOC_DIR":software_order.pdf)

```

SELECTAI 벡터인덱스 조회

```sql
col index_name format a60

select index_name, status, created from user_cloud_vector_indexes WHERE index_name = 'SAI_RAG_IDX';
INDEX_NAME                            STATUS                   CREATED
------------------------------------- ------------------------ ---------------------------------
SAI_RAG_IDX                           ENABLED                  26/02/13 00:35:18.857428 +00:00
```

SELECTAI 벡터인덱스 인덱스 물리 객체 확인

```sql
select * from tab where tname like 'VECTOR$SAI_RAG_IDX%' or tname like 'PIPELINE%';
TNAME                                                                            TABTYPE               CLUSTERID
-------------------------------------------------------------------------------- -------------------- ----------
VECTOR$SAI_RAG_IDX$74668_74675_0$IVF_FLAT_CENTROIDS                              TABLE
VECTOR$SAI_RAG_IDX$74668_74675_0$IVF_FLAT_CENTROID_PARTITIONS                    TABLE
PIPELINE$6$64_STATUS                                                          TABLE
```

벡터 인덱싱 상태 확인
```sql
SELECT ID, NAME, STATUS, LAST_MODIFIED, START_TIME, END_TIME, ERROR_MESSAGE FROM PIPELINE$6$64_STATUS;

        ID NAME                           STATUS               LAST_MODIFIED        START_TIME                     END_TIME                        ERROR_MESSAGE
---------- ------------------------------ -------------------- -------------------- ------------------------------ ------------------------------ --------------------------------------------------
         1 SPRi_AI_202404.pdf             COMPLETED            25/11/07 02:18:38.00 26/02/13 00:35:27.224206 +00:0 26/02/13 00:35:31.573885 +00:0
                                                               0000 UTC             0                              0

         2 software_order.pdf             COMPLETED            25/11/07 02:18:38.00 26/02/13 00:35:27.224407 +00:0 26/02/13 00:35:37.141106 +00:0
                                                               0000 UTC             0                              0
```
