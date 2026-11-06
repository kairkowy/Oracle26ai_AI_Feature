---------------------------------------
## Orale Synthetic Data Generation 샘플
---------------------------------------

이 문서는 Oracle26AI에서 지원하는 Synthetic Data Generation(SDG) 기능을 이용하여 샘플 데이터를 생성하는 예제입니다.
LLM 서비스, AI Profile, 타겟 테이블이 기본적으로 필요하며 샘플 row가 있으면 더 좋습니다.


---------------------------------------
-- SELECTAI_SDG profile 생성
--------------------------------------
```sql
set serverout on

BEGIN
  -- 있으면 삭제 (force => true)
  DBMS_CLOUD_AI.DROP_PROFILE(
    profile_name => 'SELECTAI_SDG',
    force        => TRUE
  );
  EXCEPTION WHEN OTHERS THEN NULL;
END;
/

BEGIN
  -- 생성
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'SELECTAI_SDG',
    attributes   => '{
      "provider":"OPENAI",
      "provider_endpoint": "http://service-ollama",
      "model": "gemma2:9b"
      }',
    status       => 'enabled',
    description  => 'Select AI profile for Synthetic Data Generation'
  );
END;
/
```

-- 기본 테이블/데이터 생성

```sql
create table med_history
(ptt_name varchar(20),
 visit_dt varchar(20),
 dr_name varchar(20),
 sympt_ptt varchar2(4000),
 pcr_reason varchar2(4000)
)

INSERT INTO med_history
VALUES (
  '김태원',
  '2025-03-03 14:23:00',
  '한철수',
  '온몸의 근육이 뻣뻣하게 결리는 느낌이에요.',
  '근육에 통증 유발점(Trigger point)이 확인. 스트레스나 잘못된 자세로 인해 악화됨.'
);
```

프로파일 활성화

```sql
EXECUTE DBMS_CLOUD_AI.SET_PROFILE('SELECTAI_SDG');
```

SDG 함수 이용하여 데이터 생성 실행

```sql
BEGIN
  DBMS_CLOUD_AI.GENERATE_SYNTHETIC_DATA(
    profile_name => 'SELECTAI_SDG',
    object_name  => 'MED_HISTORY',
    owner_name   => 'LABADMIN',
    record_count => 100,
    user_prompt  => '
      MED_HISTORY에 있는 데이터를 참해서 데이터를 생산해.
      모든 컬럼 데이터는 한국어로 작성.
      ptt_name은 한국인 이름.
      dr_name은 한국인 이름.
      visit_dt는 YYYY-MM-DD HH24:MI:SS 형식이며 중복은 안됨, .
      sympt_ptt는 환자가 말하는 증상으로, 환자별로 다양하게 증상을 만들고, 자연스러운 한국어 문장으로 작성해.
      pcr_reason은 sympt_ptt 내용에 부합하게 의사의 처방 사유를 자연스럽고 구체적인 한국어 문장으로 작성.'
    );
END;
/
```

데이터 확인

```sql
select * from med_history
fetch first 10 rows only;

PTT_NAME   VISIT_DT             DR_NAME    SYMPT_PTT                                PCR_REASON
---------- -------------------- ---------- ---------------------------------------- ------------------------------------------------------------
김태원     2025-03-03 14:23:00  한철수     온몸의 근육이 뻣뻣하게 결리는 느낌이에요 근육에 통증 유발점(Trigger point)이 확인. 스트레스나 잘못된
                                           .                                        자세로 인해 악화됨.

김민수     2023-10-26 14:30:00  박민지     어지러움과 두통이 심합니다.              어지러움과 두통 증상을 보이는 경우, 혈압 변화나 뇌압 상승 등
                                                                                    을 의심하여 추가 검사를 진행합니다.

이정현     2023-10-26 15:45:00  이수현     최근 며칠 동안 발열과 기침이 심합니다.   발열과 기침 증상은 감기나 독감 등의 감염성 질환을 의심하여,
                                                                                    추가 검사와 치료를 진행합니다.

최지우     2023-10-26 16:10:00  김태희     식욕이 없고, 복통이 심합니다.            식욕 부진과 복통은 위장관 질환이나 감염 등을 의심하여, 추가
                                                                                    검사와 치료를 진행합니다.

박지훈     2023-10-26 17:25:00  강민수     피로감이 심하고, 잠을 잘 수 없습니다.    피로감과 불면증은 스트레스, 우울증 등의 정신적 요인이나 질환
                                                                                    을 의심하여, 추가 검사와 치료를 진행합니다.
```
