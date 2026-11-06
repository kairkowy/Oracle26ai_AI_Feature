### 샘플 데이터 생성 스크립트

데이터 출처 : 공공데이터 포털 

데이터명 : 제주특별자치도_개별관광(FIT)_증가에_따른_제주_관광객_소비패턴_변화_분석_BC카드_빅데이터_내국인관광객_20170216

파일명 : jeju_tour_hist_bc_20170216.txtx


테이블 생성
```sql
CREATE TABLE tour_hist (
  tr_yearmonth        VARCHAR2(20),
  visitor_type      VARCHAR2(100),
  jeju_class1      VARCHAR2(60),
  jeju_class2      VARCHAR2(60),
  market_type      VARCHAR2(100),
  visit_gender     VARCHAR2(20),
  age_grp        VARCHAR2(60),
  card_amount    NUMBER,
  card_tr_cnt    NUMBER,
  amountpertr    NUMBER,
  tr_date  DATE
);

```

디렉토리 생성

```sql

crete or replace directory DUMPDIR as '/home/dev01/labs/data';

```

로더 콘트롤 파일 생성(loader.ctl)

```sql
OPTIONS (SKIP = 1)
LOAD DATA
CHARACTERSET UTF8
INFILE './jeju_tour_hist_bc_20170216-utf8.txt'
INTO TABLE tour_hist
APPEND
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  tr_yearmonth        CHAR,
  visitor_type      CHAR,
  jeju_class1      CHAR,
  jeju_class2      CHAR,
  market_type    CHAR,
  visit_gender   CHAR,
  age_grp        CHAR,
  card_amount    INTEGER EXTERNAL,
  card_tr_cnt    INTEGER EXTERNAL,
  amountpertr     INTEGER EXTERNAL,
  tr_date  DATE "YYYY-MM-DD"
)

```

sqlldr labadmin/Welcome1@orclpdb1 control=control.ctl

