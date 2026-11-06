-------------------------------------------------
### Annotations - 테이블, 컬럼에 대한 Annotation 예제
-------------------------------------------------

```sql
-- 테이블 Annotation 추가

ALTER TABLE tour_hist 
ANNOTATIONS (
  description '제주 관광객 카드 소비 통계 테이블. 관광객 유형, 업종, 성별, 연령대별 카드 이용 금액 및 이용 건수를 포함한다.'
);

-- 컬럼 Annotation 추가
ALTER TABLE tour_hist MODIFY (
  tr_yearmonth  ANNOTATIONS (meaning '데이터 기준 연월. 예: 2024-01'),
  visitor_type  ANNOTATIONS (meaning '관광객 구분. 예: 내국인 관광객, 외국인 관광객'),
  jeju_class1   ANNOTATIONS (meaning '제주 지역 관광 분류 대분류'),
  jeju_class2   ANNOTATIONS (meaning '제주 지역 관광 분류 중분류'),
  market_type   ANNOTATIONS (meaning '카드 사용이 발생한 업종명. 예: 음식점, 숙박업, 관광지'),
  visit_gender  ANNOTATIONS (meaning '카드 사용자의 성별 구분(남/여)'),
  age_grp       ANNOTATIONS (meaning '카드 사용자의 연령대 구간. 예: 20대, 30대, 40대'),
  card_tr_cnt   ANNOTATIONS (
                 meaning '해당 조건에서 발생한 카드 결제 건수',
                 SYNONYMS    '이용건수'
               ),
  tr_date       ANNOTATIONS (
                 meaning '데이터가 집계된 기준 날짜',
                 SYNONYMS    '집계일,결제일'
               )
)
;

ALTER TABLE tour_hist MODIFY (
  card_amount ANNOTATIONS (
    description '해당 조건에서 발생한 카드 결제 총 금액. 금액 단위는 원(KRW)이다.',
    nl_synonym  '카드이용금액,카드이용총금액,이용총액,결제총액,매출금액,합계금액',
    unit        'KRW',
    format_hint   '합계 또는 금액 표시 요청 시 TO_CHAR를 사용해 천단위 콤마와 원 단위를 붙인다. 예: TO_CHAR(value, ''FM999,999,999,999,999'') || '' 원''',
    display_label '카드이용금액합계(원)'
  ));

ALTER TABLE tour_hist MODIFY (
  amountpertr ANNOTATIONS (
    description   '카드 결제 1건당 평균 이용 금액. 금액 단위는 원(KRW)이다.',
    nl_synonym    '건당평균금액,평균결제금액,평균이용금액,단가,객단가',
    unit          'KRW',
    format_hint   '평균 금액 표시 요청 시 TO_CHAR를 사용해 천단위 콤마와 원 단위를 붙인다. 예: TO_CHAR(value, ''FM999,999,999,999,999'') || '' 원''',
    display_label '평균이용금액(원)'
  )
);

-- 컬럼 Annotation 삭제

ALTER TABLE tour_hist MODIFY (
  tr_yearmonth ANNOTATIONS (DROP MEANING)
);

-- Annotation의 삭제는 하나씩 DROP 해야함.
-- ALTER TABLE DEPARTMENTS MODIFY ( DEPARTMENT_NAME ANNOTATIONS (drop "Display Label", drop SYNONYMS));
-- ALTER TABLE DEPARTMENTS MODIFY ( DEPARTMENT_ID ANNOTATIONS (drop "Display Label", drop SYNONYMS));

ALTER TABLE DEPARTMENTS MODIFY (
  DEPARTMENT_NAME ANNOTATIONS (ADD "Display Label" '부서명', ADD "SYNONYMS" '부서명'),
  DEPARTMENT_ID ANNOTATIONS (ADD "Display Label" '부서코드', ADD "SYNONYMS" '부서ID')
  )
;

ALTER TABLE JOBS MODIFY ( JOB_ID ANNOTATIONS (drop "Display Label", drop SYNONYMS));
ALTER TABLE JOBS MODIFY ( JOB_TITLE ANNOTATIONS (drop "Display Label", drop SYNONYMS));

ALTER TABLE JOBS MODIFY (
  JOB_ID ANNOTATIONS (ADD "Display Label" '직무코드', ADD "SYNONYMS" '직무ID,직무계정' ),
  JOB_TITLE ANNOTATIONS (ADD "Display Label" '직무명', ADD "SYNONYMS" '직무명' )
);

ALTER TABLE EMPLOYEES MODIFY ( 
  EMPLOYEE_ID ANNOTATIONS (ADD "Display Label" '직원코드', ADD "SYNONYMS" '직원ID,직원번호,직원코드'),
  MANAGER_ID ANNOTATIONS (ADD "Display Label" '매니저', ADD "SYNONYMS" '관리자, 책임자'), 
  SALARY ANNOTATIONS (ADD "Display Label" '급여', ADD "SYNONYMS" '급여, 연봉'),
  HIRE_DATE ANNOTATIONS (ADD "Display Label" '입사일', ADD "SYNONYMS" '입사일, 채용일')
);

ALTER TABLE COUNTRIES MODIFY ( COUNTRY_ID ANNOTATIONS (drop "Display Label", drop SYNONYMS));
ALTER TABLE COUNTRIES MODIFY ( COUNTRY_NAME ANNOTATIONS (drop "Display Label", drop SYNONYMS));

ALTER TABLE COUNTRIES MODIFY (
  COUNTRY_ID ANNOTATIONS ( ADD "Display Label" '국가코드', ADD "SYNONYMS" '국가코드, 나라코드,국가번호, 나라번호'),
  COUNTRY_NAME ANNOTATIONS ( ADD "Display Label" '국가명', ADD "SYNONYMS" '국가명,나라명,나라이름,국가이름')
);

ALTER TABLE REGIONS MODIFY (
  REGION_ID ANNOTATIONS (ADD "Display Label" '권역코드', ADD "SYNONYMS" '권역코드,권역ID,지역코드,지역ID'),
  REGION_NAME ANNOTATIONS ( ADD "Display Label" '권역명', ADD "SYNONYMS" '권역이름, 권역명, 지역이름, 지역명')
);

ALTER TABLE LOCATIONS MODIFY (
  COUNTRY_ID ANNOTATIONS ( ADD "Display Label" '국가코드', ADD "SYNONYMS" '국가코드, 나라코드,국가번호, 나라번호'),
  LOCATION_ID ANNOTATIONS (ADD "Display Label" '위치코드', ADD "SYNONYMS" '위치번호')
);
