# SELECT AI 실습 계정 관리

관리자가 대상 PDB에서 `lab00`~`lab19`의 20개 계정을 준비하는 스크립트입니다. 기본 테이블스페이스는 `USERS`이며 해당 테이블스페이스의 quota를 `UNLIMITED`로 설정하고, `CONNECT`·`RESOURCE` 역할과 SH 전체 9개 테이블의 `SELECT` 권한을 부여합니다.

실행 순서는 **이 문서의 계정 생성 → [실습환경 구성](SelectAiConfigure.md)의 패키지·Wallet·ACL 설정 → 이 문서의 패키지 실행 권한 부여 → [샘플 데이터 구성](SampleDataConfig.md)**입니다. SQL*Plus 또는 SQLcl에서 SYS 등 사용자·역할·객체 권한을 관리할 수 있는 계정으로 실행합니다. SH 데이터와 `USERS` 테이블스페이스는 대상 PDB에 준비되어 있어야 합니다.

## 1. 계정 생성과 기본 권한 부여

PDB 이름과 테이블스페이스를 환경에 맞게 변경합니다. 신규 계정에 사용할 공통 실습 비밀번호를 입력합니다. 아래 입력 방식에서는 비밀번호에 큰따옴표(`"`)와 물결표(`~`)를 사용하지 않습니다. 재실행 시 기존 계정의 비밀번호는 유지하고 역할·quota·SH 조회 권한을 다시 적용합니다.

```sql
SET DEFINE ON
SET VERIFY OFF
SET ECHO OFF
SET SERVEROUTPUT ON

DEFINE LAB_PDB = orclpdb1
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
DEFINE LAB_PDB = orclpdb1
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

참고: [Oracle 사용자 생성과 quota](https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/CREATE-USER.html)
