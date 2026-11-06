# SELECT AI 실습환경 구성

이 문서는 SELECT AI 예제 실행 전 관리자가 수행할 권한·ACL 설정과 lab00의 데이터 준비를 다룹니다. Part별 프로파일은 [SELECT AI 예제](SelectAiExample.md)에서 생성합니다. `DBMS_CLOUD`·`DBMS_CLOUD_AI` 패키지 설치와 Wallet 구성은 [온프레미스 Select AI 구성 문서](../SelectAI/SelectAI_Config_Run.md)를 참고하여 먼저 완료합니다. `lab00` 계정과 SH의 전체 9개 테이블 및 데이터도 대상 PDB에 준비되어 있어야 합니다.

아래 SQL은 SQL*Plus 또는 SQLcl 기준입니다. PDB 이름, 테이블스페이스, Ollama 호스트·엔드포인트·모델은 실제 환경에 맞게 변경합니다. DB 서버에서 Ollama 호스트로 접속할 수 있어야 합니다.

| 설정 | 예시 값 | 설명 |
|---|---|---|
| 대상 PDB | `orclpdb1` | `lab00`과 SH 전체 테이블이 있는 PDB |
| 테이블스페이스 | `USERS` | `lab00`의 실습 테이블을 저장할 테이블스페이스 |
| Ollama 호스트 | `service-ollama` | ACL에는 프로토콜·포트·경로를 제외한 호스트만 지정 |
| Ollama 엔드포인트 | `http://service-ollama/v1` | 참조 문서의 프록시 구성 기준 주소 |
| 모델 | `gemma2:9b` | 참조 문서의 DB 쿼리 예시 모델. 실제 Ollama에 설치된 모델명으로 변경 |

## 1. 관리자: 실행 권한과 ACL 등록

SYS 등 CDB·PDB를 관리할 수 있는 계정으로 실행합니다. ACL은 예시의 Ollama 호스트에 대해 등록합니다.

```sql
DEFINE LAB_PDB = orclpdb1
DEFINE LAB_TABLESPACE = USERS
DEFINE OLLAMA_HOST = service-ollama

-- CDB: 참조 문서의 Cloud 패키지 서비스 계정 ACL
ALTER SESSION SET CONTAINER = CDB$ROOT;

BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => '&&OLLAMA_HOST',
    ace  => xs$ace_type(
      privilege_list => xs$name_list('connect', 'resolve'),
      principal_name => 'C##CLOUD$SERVICE',
      principal_type => xs_acl.ptype_db
    )
  );
END;
/

-- PDB: lab00 실행 권한과 데이터 접근 권한
ALTER SESSION SET CONTAINER = &&LAB_PDB;

GRANT CREATE SESSION, CREATE TABLE TO lab00;
GRANT EXECUTE ON DBMS_CLOUD TO lab00;
GRANT EXECUTE ON DBMS_CLOUD_AI TO lab00;
GRANT SELECT ON SH.COUNTRIES TO lab00;
GRANT SELECT ON SH.CUSTOMERS TO lab00;
GRANT SELECT ON SH.PRODUCTS TO lab00;
GRANT SELECT ON SH.TIMES TO lab00;
GRANT SELECT ON SH.CHANNELS TO lab00;
GRANT SELECT ON SH.PROMOTIONS TO lab00;
GRANT SELECT ON SH.SUPPLEMENTARY_DEMOGRAPHICS TO lab00;
GRANT SELECT ON SH.SALES TO lab00;
GRANT SELECT ON SH.COSTS TO lab00;

ALTER USER lab00 QUOTA 1G ON &&LAB_TABLESPACE;

-- PDB: 실습 계정에서 Ollama 서비스에 접근할 수 있도록 등록
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => '&&OLLAMA_HOST',
    ace  => xs$ace_type(
      privilege_list => xs$name_list('http', 'connect', 'resolve'),
      principal_name => 'LAB00',
      principal_type => xs_acl.ptype_db
    )
  );
END;
/

-- 대상 PDB의 ACL 등록 확인
SELECT host, principal, privilege, grant_type
FROM   dba_host_aces
WHERE  host = '&&OLLAMA_HOST'
AND    principal = 'LAB00'
ORDER BY privilege;
```

## 2. lab00: 실습 데이터 준비

이후 스크립트는 **대상 PDB에 `lab00`으로 접속한 세션**에서 실행합니다. Annotation을 직접 추가할 수 있도록 SH의 전체 9개 테이블을 `LAB00`에 복사합니다. 원본 SH 데이터는 수정하지 않습니다.

최초 준비 시 한 번 실행합니다. 이전 단계에서 `LAB00.PRODUCTS`와 기본키를 이미 만들었다면 아래의 해당 생성 구문은 생략하고 나머지 테이블을 추가합니다. 전체 데이터 복사를 위해 예시에서는 테이블스페이스 할당량을 `1G`로 설정했으며, 실제 데이터 크기에 맞게 조정합니다.

CTAS는 데이터를 일반 테이블로 복사하며 원본의 인덱스·분할·Comment·Annotation을 복제하지 않습니다. 조인 관계를 메타데이터로 제공할 수 있도록 기본키와 외래키는 복사 후 명시적으로 생성합니다.

```sql
DEFINE LAB_TABLESPACE = USERS

-- SH 전체 테이블의 데이터 복사
CREATE TABLE countries TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.countries;

CREATE TABLE customers TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.customers;

CREATE TABLE products TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.products;

CREATE TABLE times TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.times;

CREATE TABLE channels TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.channels;

CREATE TABLE promotions TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.promotions;

CREATE TABLE supplementary_demographics TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.supplementary_demographics;

CREATE TABLE sales TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.sales;

CREATE TABLE costs TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.costs;

-- 기본키 생성
ALTER TABLE countries ADD CONSTRAINT lab00_countries_pk
  PRIMARY KEY (country_id);
ALTER TABLE customers ADD CONSTRAINT lab00_customers_pk
  PRIMARY KEY (cust_id);
ALTER TABLE products ADD CONSTRAINT lab00_products_pk
  PRIMARY KEY (prod_id);
ALTER TABLE times ADD CONSTRAINT lab00_times_pk
  PRIMARY KEY (time_id);
ALTER TABLE channels ADD CONSTRAINT lab00_channels_pk
  PRIMARY KEY (channel_id);
ALTER TABLE promotions ADD CONSTRAINT lab00_promotions_pk
  PRIMARY KEY (promo_id);
ALTER TABLE supplementary_demographics ADD CONSTRAINT lab00_supp_demo_pk
  PRIMARY KEY (cust_id);

-- 외래키 생성
ALTER TABLE customers ADD CONSTRAINT lab00_customers_country_fk
  FOREIGN KEY (country_id) REFERENCES countries (country_id);
ALTER TABLE sales ADD CONSTRAINT lab00_sales_product_fk
  FOREIGN KEY (prod_id) REFERENCES products (prod_id);
ALTER TABLE sales ADD CONSTRAINT lab00_sales_customer_fk
  FOREIGN KEY (cust_id) REFERENCES customers (cust_id);
ALTER TABLE sales ADD CONSTRAINT lab00_sales_time_fk
  FOREIGN KEY (time_id) REFERENCES times (time_id);
ALTER TABLE sales ADD CONSTRAINT lab00_sales_channel_fk
  FOREIGN KEY (channel_id) REFERENCES channels (channel_id);
ALTER TABLE sales ADD CONSTRAINT lab00_sales_promo_fk
  FOREIGN KEY (promo_id) REFERENCES promotions (promo_id);
ALTER TABLE costs ADD CONSTRAINT lab00_costs_product_fk
  FOREIGN KEY (prod_id) REFERENCES products (prod_id);
ALTER TABLE costs ADD CONSTRAINT lab00_costs_time_fk
  FOREIGN KEY (time_id) REFERENCES times (time_id);
ALTER TABLE costs ADD CONSTRAINT lab00_costs_channel_fk
  FOREIGN KEY (channel_id) REFERENCES channels (channel_id);
ALTER TABLE costs ADD CONSTRAINT lab00_costs_promo_fk
  FOREIGN KEY (promo_id) REFERENCES promotions (promo_id);

-- 전체 테이블 데이터 확인
SELECT 'PRODUCTS' AS table_name, COUNT(*) AS row_count FROM products
UNION ALL SELECT 'SALES', COUNT(*) FROM sales
UNION ALL SELECT 'COSTS', COUNT(*) FROM costs
UNION ALL SELECT 'CUSTOMERS', COUNT(*) FROM customers
UNION ALL SELECT 'COUNTRIES', COUNT(*) FROM countries
UNION ALL SELECT 'TIMES', COUNT(*) FROM times
UNION ALL SELECT 'CHANNELS', COUNT(*) FROM channels
UNION ALL SELECT 'PROMOTIONS', COUNT(*) FROM promotions
UNION ALL SELECT 'SUPPLEMENTARY_DEMOGRAPHICS', COUNT(*)
  FROM supplementary_demographics;
```

`SUPPLEMENTARY_DEMOGRAPHICS.CUST_ID`와 `CUSTOMERS.CUST_ID`는 논리적으로 연결됩니다. 원본 SH 정의와 동일하게 이 관계에는 별도 외래키를 추가하지 않습니다.

환경 구성이 끝나면 [SELECT AI 예제의 실행 전 확인](SelectAiExample.md#실행-전-확인)으로 이동합니다.
