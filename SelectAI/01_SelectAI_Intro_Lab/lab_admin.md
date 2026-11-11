# SELECT AI 실습 계정 관리

관리자가 대상 PDB에서 `lab00`~`lab19`의 20개 계정을 준비하는 스크립트입니다. 기본 테이블스페이스는 `USERS`이며 해당 테이블스페이스의 quota를 `UNLIMITED`로 설정하고, `CONNECT`·`RESOURCE` 역할과 SH 전체 9개 테이블의 `SELECT` 권한을 부여합니다. 계정별 데이터 복사와 기본키·외래키 생성도 이 문서에서 준비합니다.

실행 순서는 **이 문서의 계정 생성 → [실습환경 구성](SelectAiConfigure.md)의 패키지·Wallet·ACL 설정 → 이 문서의 패키지 실행 권한 부여·데이터 준비 → [샘플 데이터 구성](SampleDataConfig.md)의 Annotation 등록**입니다. 1~3단원은 SQL*Plus 또는 SQLcl에서 SYS 등 사용자·역할·객체 권한을 관리할 수 있는 계정으로 실행합니다. 4~5단원은 각 실습 계정으로 접속하여 실행합니다. 5단원의 클린징은 실습 종료 후 필요한 경우 수행합니다. SH 데이터와 `USERS` 테이블스페이스는 대상 PDB에 준비되어 있어야 합니다.

## 1. 계정 생성과 기본 권한 부여

실습 PDB는 `orclpdb2`입니다. 테이블스페이스는 환경에 맞게 변경합니다. 신규 계정에 사용할 공통 실습 비밀번호를 입력합니다. 아래 입력 방식에서는 비밀번호에 큰따옴표(`"`)와 물결표(`~`)를 사용하지 않습니다. 재실행 시 기존 계정의 비밀번호는 유지하고 역할·quota·SH 조회 권한을 다시 적용합니다.

```sql
SET DEFINE ON
SET VERIFY OFF
SET ECHO OFF
SET SERVEROUTPUT ON

DEFINE LAB_PDB = orclpdb2
DEFINE LAB_TABLESPACE = USERS
ACCEPT LAB_PASSWORD CHAR PROMPT '신규 실습 계정의 공통 비밀번호: ' HIDE

WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
ALTER SESSION SET CONTAINER = &&LAB_PDB;

DECLARE
  l_user        VARCHAR2(30);
  l_user_sql    VARCHAR2(128);
  l_password    VARCHAR2(128) := q'~&&LAB_PASSWORD~';
  l_tablespace  VARCHAR2(128) := UPPER('&&LAB_TABLESPACE');
  l_table_name  VARCHAR2(128);
  l_count       PLS_INTEGER;
  l_tables      SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST(
    'COUNTRIES', 'CUSTOMERS', 'PRODUCTS', 'TIMES', 'CHANNELS',
    'PROMOTIONS', 'SUPPLEMENTARY_DEMOGRAPHICS', 'SALES', 'COSTS'
  );
BEGIN
  IF SYS_CONTEXT('USERENV', 'CON_NAME') = 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20001, '대상 PDB에서 실행하십시오.');
  END IF;
  IF l_password IS NULL OR INSTR(l_password, '"') > 0
     OR INSTR(l_password, '~') > 0 THEN
    RAISE_APPLICATION_ERROR(-20002, '비밀번호를 입력하고 큰따옴표와 물결표는 제외하십시오.');
  END IF;

  SELECT COUNT(*) INTO l_count
  FROM dba_tablespaces
  WHERE tablespace_name = l_tablespace AND contents = 'PERMANENT';
  IF l_count <> 1 THEN
    RAISE_APPLICATION_ERROR(-20003, '지정한 영구 테이블스페이스가 없습니다.');
  END IF;

  -- 사용자 생성 전에 SH의 전체 대상 테이블 존재 여부 확인
  FOR j IN 1..l_tables.COUNT LOOP
    l_table_name := l_tables(j);
    SELECT COUNT(*) INTO l_count
    FROM dba_tables
    WHERE owner = 'SH' AND table_name = l_table_name;
    IF l_count <> 1 THEN
      RAISE_APPLICATION_ERROR(-20004, 'SH.' || l_tables(j) || ' 테이블이 없습니다.');
    END IF;
  END LOOP;

  FOR i IN 0..19 LOOP
    l_user := 'LAB' || TO_CHAR(i, 'FM00');
    l_user_sql := DBMS_ASSERT.ENQUOTE_NAME(l_user, FALSE);

    SELECT COUNT(*) INTO l_count FROM dba_users WHERE username = l_user;
    IF l_count = 0 THEN
      EXECUTE IMMEDIATE 'CREATE USER ' || l_user_sql ||
        ' IDENTIFIED BY "' || l_password || '" DEFAULT TABLESPACE ' ||
        DBMS_ASSERT.ENQUOTE_NAME(l_tablespace, FALSE);
    END IF;

    EXECUTE IMMEDIATE 'ALTER USER ' || l_user_sql ||
      ' DEFAULT TABLESPACE ' || DBMS_ASSERT.ENQUOTE_NAME(l_tablespace, FALSE);
    EXECUTE IMMEDIATE 'ALTER USER ' || l_user_sql ||
      ' QUOTA UNLIMITED ON ' || DBMS_ASSERT.ENQUOTE_NAME(l_tablespace, FALSE);
    EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE TO ' || l_user_sql;

    FOR j IN 1..l_tables.COUNT LOOP
      EXECUTE IMMEDIATE 'GRANT SELECT ON SH.' ||
        DBMS_ASSERT.ENQUOTE_NAME(l_tables(j), FALSE) || ' TO ' || l_user_sql;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(l_user || ': 계정·역할·quota·SH SELECT 권한 설정 완료');
  END LOOP;
END;
/

UNDEFINE LAB_PASSWORD
WHENEVER SQLERROR CONTINUE NONE
```

## 2. 패키지 실행 권한 부여

[실습환경 구성](SelectAiConfigure.md)의 `DBMS_CLOUD` 패키지 설치를 완료한 뒤 대상 PDB에서 실행합니다. 실습 계정에는 패키지 사용 권한을 부여하고, ACL 등록은 관리자 계정으로 수행합니다.

```sql
DEFINE LAB_PDB = orclpdb2
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
ALTER SESSION SET CONTAINER = &&LAB_PDB;

DECLARE
  l_user_sql VARCHAR2(128);
BEGIN
  IF SYS_CONTEXT('USERENV', 'CON_NAME') = 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20001, '대상 PDB에서 실행하십시오.');
  END IF;
  FOR i IN 0..19 LOOP
    l_user_sql := DBMS_ASSERT.ENQUOTE_NAME('LAB' || TO_CHAR(i, 'FM00'), FALSE);
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON DBMS_CLOUD TO ' || l_user_sql;
    EXECUTE IMMEDIATE 'GRANT EXECUTE ON DBMS_CLOUD_AI TO ' || l_user_sql;
  END LOOP;
END;
/

WHENEVER SQLERROR CONTINUE NONE
```

## 3. 설정 확인

대상 PDB에서 계정 20개, 계정별 역할 2개, SH 테이블 조회 권한 9개와 패키지 실행 권한 2개가 준비되었는지 확인합니다. `DBA_TS_QUOTAS.MAX_BYTES`의 `-1`은 해당 테이블스페이스에 대한 무제한 quota입니다.

```sql
SELECT username, account_status, default_tablespace
FROM dba_users
WHERE REGEXP_LIKE(username, '^LAB(0[0-9]|1[0-9])$')
ORDER BY username;

SELECT username, tablespace_name, bytes, max_bytes
FROM dba_ts_quotas
WHERE REGEXP_LIKE(username, '^LAB(0[0-9]|1[0-9])$')
AND tablespace_name = UPPER('&&LAB_TABLESPACE')
ORDER BY username;

SELECT grantee, granted_role, default_role
FROM dba_role_privs
WHERE REGEXP_LIKE(grantee, '^LAB(0[0-9]|1[0-9])$')
AND granted_role IN ('CONNECT', 'RESOURCE')
ORDER BY grantee, granted_role;

SELECT grantee, COUNT(*) AS sh_select_count
FROM dba_tab_privs
WHERE REGEXP_LIKE(grantee, '^LAB(0[0-9]|1[0-9])$')
AND owner = 'SH' AND privilege = 'SELECT'
AND table_name IN (
  'COUNTRIES', 'CUSTOMERS', 'PRODUCTS', 'TIMES', 'CHANNELS',
  'PROMOTIONS', 'SUPPLEMENTARY_DEMOGRAPHICS', 'SALES', 'COSTS'
)
GROUP BY grantee
ORDER BY grantee;

SELECT grantee, table_name AS package_name, privilege
FROM dba_tab_privs
WHERE REGEXP_LIKE(grantee, '^LAB(0[0-9]|1[0-9])$')
AND table_name IN ('DBMS_CLOUD', 'DBMS_CLOUD_AI')
AND privilege = 'EXECUTE'
ORDER BY grantee, table_name;
```

## 4. 실습 계정별 데이터 준비

**원본 SH 샘플 데이터 설치·적재는 반드시 SQLcl로 실행합니다.** `sh_install.sql`이 호출하는 CSV 적재 구문은 SQLcl의 `SET LOAD`·`LOAD` 명령을 사용하므로 SQL*Plus에서는 실행되지 않습니다. 대상 PDB `orclpdb2`에서 설치 후 Verification의 9개 테이블 모두 `provided`와 `actual` 건수가 일치하는지 확인한 뒤 실습 계정으로 복사합니다. [Oracle SH 설치 안내](https://github.com/oracle-samples/db-sample-schemas/blob/main/sales_history/README.md)

이후 스크립트는 **대상 PDB에 본인의 실습 계정(`lab00`~`lab19`)으로 접속한 세션**에서 실행합니다. 각 계정의 생성·역할·조회 권한·테이블스페이스 quota는 앞 단원에서 준비합니다. SH의 전체 9개 테이블을 입력한 계정에 복사하여 약 20명이 독립적으로 실습합니다. 원본 SH 데이터는 수정하지 않습니다.

최초 준비 시 한 번 실행합니다. 이전 단계에서 본인 계정의 `PRODUCTS`와 기본키를 이미 만들었다면 아래의 해당 생성 구문은 생략하고 나머지 테이블을 추가합니다. 이 문서의 계정 생성 단계에서 각 계정의 `USERS` 테이블스페이스 quota를 `UNLIMITED`로 설정합니다.

CTAS는 데이터를 일반 테이블로 복사하며 원본의 인덱스·분할·Comment·Annotation을 복제하지 않습니다. 조인 관계를 메타데이터로 제공할 수 있도록 기본키와 외래키는 복사 후 명시적으로 생성합니다.

`ACCEPT`로 입력한 계정명을 SQL*Plus의 DEFINE 치환 변수 `LAB_USER`에 저장하여 사용합니다. Enter만 누르면 `lab00`을 사용합니다. 입력 없이 지정하려면 `ACCEPT` 줄 대신 `DEFINE LAB_USER = lab07`처럼 설정합니다. 입력 계정과 실제 접속 계정이 다르면 작업을 중단합니다.

```sql
SET DEFINE ON
ACCEPT LAB_USER CHAR DEFAULT 'lab00' PROMPT '실습 계정(lab00~lab19, 기본 lab00): '
DEFINE LAB_USER
DEFINE LAB_TABLESPACE = USERS

WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
BEGIN
  IF NOT REGEXP_LIKE(UPPER('&&LAB_USER'), '^LAB(0[0-9]|1[0-9])$') THEN
    RAISE_APPLICATION_ERROR(-20001, '실습 계정은 lab00~lab19 중 하나를 입력하십시오.');
  END IF;
  IF USER <> UPPER('&&LAB_USER') THEN
    RAISE_APPLICATION_ERROR(-20002, '입력한 실습 계정으로 접속한 후 실행하십시오.');
  END IF;
END;
/

-- SH 전체 테이블의 데이터 복사
CREATE TABLE &&LAB_USER..countries TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.countries;

CREATE TABLE &&LAB_USER..customers TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.customers;

CREATE TABLE &&LAB_USER..products TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.products;

CREATE TABLE &&LAB_USER..times TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.times;

CREATE TABLE &&LAB_USER..channels TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.channels;

CREATE TABLE &&LAB_USER..promotions TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.promotions;

CREATE TABLE &&LAB_USER..supplementary_demographics TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.supplementary_demographics;

CREATE TABLE &&LAB_USER..sales TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.sales;

CREATE TABLE &&LAB_USER..costs TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.costs;

-- 기본키 생성
ALTER TABLE &&LAB_USER..countries ADD CONSTRAINT &&LAB_USER._countries_pk
  PRIMARY KEY (country_id);
ALTER TABLE &&LAB_USER..customers ADD CONSTRAINT &&LAB_USER._customers_pk
  PRIMARY KEY (cust_id);
ALTER TABLE &&LAB_USER..products ADD CONSTRAINT &&LAB_USER._products_pk
  PRIMARY KEY (prod_id);
ALTER TABLE &&LAB_USER..times ADD CONSTRAINT &&LAB_USER._times_pk
  PRIMARY KEY (time_id);
ALTER TABLE &&LAB_USER..channels ADD CONSTRAINT &&LAB_USER._channels_pk
  PRIMARY KEY (channel_id);
ALTER TABLE &&LAB_USER..promotions ADD CONSTRAINT &&LAB_USER._promotions_pk
  PRIMARY KEY (promo_id);
ALTER TABLE &&LAB_USER..supplementary_demographics ADD CONSTRAINT &&LAB_USER._supp_demo_pk
  PRIMARY KEY (cust_id);

-- 외래키 생성
ALTER TABLE &&LAB_USER..customers ADD CONSTRAINT &&LAB_USER._customers_country_fk
  FOREIGN KEY (country_id) REFERENCES &&LAB_USER..countries (country_id);
ALTER TABLE &&LAB_USER..sales ADD CONSTRAINT &&LAB_USER._sales_product_fk
  FOREIGN KEY (prod_id) REFERENCES &&LAB_USER..products (prod_id);
ALTER TABLE &&LAB_USER..sales ADD CONSTRAINT &&LAB_USER._sales_customer_fk
  FOREIGN KEY (cust_id) REFERENCES &&LAB_USER..customers (cust_id);
ALTER TABLE &&LAB_USER..sales ADD CONSTRAINT &&LAB_USER._sales_time_fk
  FOREIGN KEY (time_id) REFERENCES &&LAB_USER..times (time_id);
ALTER TABLE &&LAB_USER..sales ADD CONSTRAINT &&LAB_USER._sales_channel_fk
  FOREIGN KEY (channel_id) REFERENCES &&LAB_USER..channels (channel_id);
ALTER TABLE &&LAB_USER..sales ADD CONSTRAINT &&LAB_USER._sales_promo_fk
  FOREIGN KEY (promo_id) REFERENCES &&LAB_USER..promotions (promo_id);
ALTER TABLE &&LAB_USER..costs ADD CONSTRAINT &&LAB_USER._costs_product_fk
  FOREIGN KEY (prod_id) REFERENCES &&LAB_USER..products (prod_id);
ALTER TABLE &&LAB_USER..costs ADD CONSTRAINT &&LAB_USER._costs_time_fk
  FOREIGN KEY (time_id) REFERENCES &&LAB_USER..times (time_id);
ALTER TABLE &&LAB_USER..costs ADD CONSTRAINT &&LAB_USER._costs_channel_fk
  FOREIGN KEY (channel_id) REFERENCES &&LAB_USER..channels (channel_id);
ALTER TABLE &&LAB_USER..costs ADD CONSTRAINT &&LAB_USER._costs_promo_fk
  FOREIGN KEY (promo_id) REFERENCES &&LAB_USER..promotions (promo_id);

-- 전체 테이블 데이터 확인
SELECT 'PRODUCTS' AS table_name, COUNT(*) AS row_count FROM &&LAB_USER..products
UNION ALL SELECT 'SALES', COUNT(*) FROM &&LAB_USER..sales
UNION ALL SELECT 'COSTS', COUNT(*) FROM &&LAB_USER..costs
UNION ALL SELECT 'CUSTOMERS', COUNT(*) FROM &&LAB_USER..customers
UNION ALL SELECT 'COUNTRIES', COUNT(*) FROM &&LAB_USER..countries
UNION ALL SELECT 'TIMES', COUNT(*) FROM &&LAB_USER..times
UNION ALL SELECT 'CHANNELS', COUNT(*) FROM &&LAB_USER..channels
UNION ALL SELECT 'PROMOTIONS', COUNT(*) FROM &&LAB_USER..promotions
UNION ALL SELECT 'SUPPLEMENTARY_DEMOGRAPHICS', COUNT(*)
  FROM &&LAB_USER..supplementary_demographics;

WHENEVER SQLERROR CONTINUE NONE
```

`SUPPLEMENTARY_DEMOGRAPHICS.CUST_ID`와 `CUSTOMERS.CUST_ID`는 논리적으로 연결됩니다. 원본 SH 정의와 동일하게 이 관계에는 별도 외래키를 추가하지 않습니다.

데이터 준비 후 [샘플 데이터 구성의 Annotation 등록](SampleDataConfig.md#2-실습-계정별-annotation-등록)으로 이동합니다.

참고: [Oracle 사용자 생성과 quota](https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/CREATE-USER.html)

## 5. 실습 데이터·테이블 클린징

실습을 마친 뒤 본인 계정의 데이터를 정리할 때 사용합니다. 먼저 대상 계정을 확인한 후 **데이터만 삭제**하거나 **테이블을 삭제**하는 작업 중 필요한 하나를 선택합니다. 대상은 실습 계정에 복사한 9개 테이블이며, 원본 SH 데이터는 유지합니다.

### 5.1 대상 계정 확인

정리할 실습 계정으로 대상 PDB에 접속한 뒤 실행합니다. 입력 계정이 `lab00`~`lab19` 범위를 벗어나거나 접속 계정과 다르면 SQL*Plus 또는 SQLcl을 종료하여 후속 삭제를 중단합니다.

```sql
SET DEFINE ON
ACCEPT LAB_USER CHAR DEFAULT 'lab00' PROMPT '정리할 실습 계정(lab00~lab19, 기본 lab00): '
DEFINE LAB_USER

WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
BEGIN
  IF NOT REGEXP_LIKE(UPPER('&&LAB_USER'), '^LAB(0[0-9]|1[0-9])$') THEN
    RAISE_APPLICATION_ERROR(-20001, '실습 계정은 lab00~lab19 중 하나를 입력하십시오.');
  END IF;
  IF USER <> UPPER('&&LAB_USER') THEN
    RAISE_APPLICATION_ERROR(-20002, '정리할 실습 계정으로 접속한 후 실행하십시오.');
  END IF;
END;
/

SELECT USER AS cleanup_user,
       SYS_CONTEXT('USERENV', 'CON_NAME') AS current_pdb
FROM dual;
```

### 5.2 데이터만 삭제

테이블 구조, 기본키·외래키와 Annotation을 유지하고 모든 행을 삭제합니다. 외래키 관계에 따라 자식 테이블부터 삭제합니다. `COMMIT`으로 삭제를 확정합니다.

```sql
DELETE FROM &&LAB_USER..sales;
DELETE FROM &&LAB_USER..costs;
DELETE FROM &&LAB_USER..supplementary_demographics;
DELETE FROM &&LAB_USER..customers;
DELETE FROM &&LAB_USER..countries;
DELETE FROM &&LAB_USER..products;
DELETE FROM &&LAB_USER..times;
DELETE FROM &&LAB_USER..channels;
DELETE FROM &&LAB_USER..promotions;

COMMIT;
WHENEVER SQLERROR CONTINUE NONE
```

데이터 삭제 후 다시 실습하려면 테이블 생성·키 생성은 반복하지 않고, 각 테이블에 `INSERT INTO 실습계정.테이블 SELECT * FROM SH.테이블` 방식으로 부모 테이블부터 데이터를 적재합니다.

### 5.3 테이블 삭제

테이블과 해당 테이블의 데이터·제약조건·Annotation을 함께 제거합니다. 자식 테이블부터 삭제하며, DDL은 자동 커밋됩니다. 다시 실습하려면 [이 문서의 데이터 준비](#4-실습-계정별-데이터-준비)와 [샘플 데이터 구성의 Annotation 등록](SampleDataConfig.md#2-실습-계정별-annotation-등록)을 실행합니다.

```sql
DROP TABLE &&LAB_USER..sales;
DROP TABLE &&LAB_USER..costs;
DROP TABLE &&LAB_USER..supplementary_demographics;
DROP TABLE &&LAB_USER..customers;
DROP TABLE &&LAB_USER..countries;
DROP TABLE &&LAB_USER..products;
DROP TABLE &&LAB_USER..times;
DROP TABLE &&LAB_USER..channels;
DROP TABLE &&LAB_USER..promotions;

WHENEVER SQLERROR CONTINUE NONE
```

실습 사용자, 권한·ACL, Wallet과 Select AI 프로파일은 이 클린징 작업의 대상에 포함하지 않습니다.
