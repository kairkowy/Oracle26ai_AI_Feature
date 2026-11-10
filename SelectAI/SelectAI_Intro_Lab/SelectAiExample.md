# SELECT AI 예제

## 예제 개요

이 예제는 **Annotation을 활용하여 자연어 질문에서 생성되는 SQL의 정확도를 높이는 방법**을 실습합니다. Annotation에 테이블·컬럼의 업무 의미와 해석에 필요한 정보를 제공하고, 적용 전후의 생성 SQL과 조회 결과를 비교합니다.

| 항목 | 내용 |
|---|---|
| 실습 데이터 | Oracle 샘플 `SH`(Sales History) 스키마의 전체 9개 테이블을 각 실습 계정에 복사한 데이터 |
| 실습 계정 | `lab00`~`lab19` 중 본인 계정 |
| 비교 방식 | 동일한 데이터와 자연어 질문을 사용하여 Annotation 적용 전후 비교 |
| 확인 항목 | 테이블·컬럼 선택, 조인 관계, 조건과 집계의 정확성 |

예제 스크립트는 이 문서의 SQL 코드 블록에 직접 작성합니다.

실습 데이터의 구조와 내용은 [샘플 데이터 구성](SampleDataConfig.md#1-실습-데이터-sh-스키마)에서 확인합니다.

## 질문 예제

단일 테이블 질문 2개와 조인 질문 2개로 구성합니다. 아래 업무 정의는 **이 실습에서 정한 규칙**입니다.

### 단일 테이블 질문

| 번호 | 자연어 질문 | Part 2에서 Annotation으로 제공할 업무 정의 |
|---|---|---|
| 1 | 상품 대분류별 상품 수를 많은 순서로 보여줘. | 대분류는 `PROD_CATEGORY`입니다. 기본 비교용 질문입니다. |
| 2 | 야구용품 중 고가 상품의 상품명과 정가를 보여줘. | 야구용품은 `PROD_CATEGORY = 'Baseball'`, 고가 상품은 `PROD_LIST_PRICE >= 100`입니다. |

사용 테이블: `PRODUCTS`.

### 조인 질문

| 번호 | 자연어 질문 | 사용 테이블과 Part 2에서 Annotation으로 제공할 업무 정의 |
|---|---|---|
| 3 | 연도별 야구용품 매출액을 보여줘. | `PRODUCTS`·`SALES`·`TIMES`를 사용합니다. 야구용품은 `PROD_CATEGORY = 'Baseball'`, 연도는 `TIMES.CALENDAR_YEAR`, 매출액은 `SUM(SALES.AMOUNT_SOLD)`입니다. `PROD_ID`와 `TIME_ID`로 조인합니다. |
| 4 | 국가별 고가 야구용품 매출액을 보여줘. | `PRODUCTS`·`SALES`·`CUSTOMERS`·`COUNTRIES`를 사용합니다. 야구용품은 `PROD_CATEGORY = 'Baseball'`, 고가 상품은 `PROD_LIST_PRICE >= 100`, 국가는 고객의 `COUNTRY_NAME`, 매출액은 `SUM(SALES.AMOUNT_SOLD)`입니다. `PROD_ID`, `CUST_ID`, `COUNTRY_ID`로 조인합니다. |

두 파트에서는 **표의 자연어 질문을 동일하게 사용**합니다. Part 1에서는 업무 정의를 프롬프트에 추가하지 않고, Part 2에서는 업무 정의를 Annotation으로 제공합니다. SQL이 실행되는지뿐 아니라 **정해진 업무 규칙에 맞는 조건·계산식·집계를 생성하는지**를 비교합니다.

## 실행 전 확인

[SELECT AI 환경구성](SelectAiConfigure.md)의 관리자 설정, [실습 계정 관리](lab_admin.md#4-실습-계정별-데이터-준비)의 데이터 준비와 [샘플 데이터 구성](SampleDataConfig.md)의 Annotation 등록을 먼저 완료합니다. 이후 스크립트는 SQL*Plus 또는 SQLcl에서 **실습 PDB `orclpdb2`에 본인의 실습 계정(`lab00`~`lab19`)으로 접속한 세션**에서 실행합니다. Part 1은 등록된 Annotation을 사용하지 않고, Part 2는 같은 Annotation을 사용합니다.

### ACL 확인

Ollama 호스트는 구성 문서에서 등록한 값과 동일하게 지정합니다. `USER_HOST_ACES`에서 현재 실습 계정의 호스트 접근 권한을 확인합니다. CDB의 서비스 계정 ACL은 구성 문서에 따라 관리자가 확인합니다.

```sql
DEFINE OLLAMA_HOST = service-ollama

SELECT host, lower_port, upper_port, privilege
FROM   user_host_aces
WHERE  host = '&&OLLAMA_HOST'
ORDER BY privilege;
```

예시 구성에서는 `http`, `connect`, `resolve` 권한이 표시되어야 합니다. 이 조회는 ACL 확인이며, 실제 Ollama 서비스의 실행 상태와 모델 응답까지 확인하는 것은 아닙니다.

### 데이터 확인

실습 대상은 SH의 전체 9개 테이블을 각 실습 계정에 복사한 데이터입니다. 모든 테이블에 데이터가 준비되었는지 확인하고, 상품의 주요 컬럼 값도 조회합니다.

```sql
SELECT USER AS current_user,
       SYS_CONTEXT('USERENV', 'CON_NAME') AS current_pdb
FROM dual;

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

SELECT prod_id, prod_name, prod_category, prod_subcategory,
       prod_list_price, prod_min_price
FROM products
ORDER BY prod_id
FETCH FIRST 5 ROWS ONLY;
```

## Part 1. Annotation을 사용하지 않는 예제

Annotation을 사용하지 않은 상태에서 자연어 질문으로 SQL을 생성·실행합니다. 생성된 SQL과 기대 결과를 비교하여 업무 의미가 충분히 반영되는지 확인합니다.

### 프로파일 생성과 적용: SELECTAI_PRODUCTS_NOANN

Ollama 엔드포인트와 모델명을 실제 환경에 맞게 변경합니다. 인증 없는 Ollama 프록시 구성이므로 `credential_name`은 지정하지 않습니다. `/v1` 경로는 23.26.2 구성 예시이며, 설치 버전과 프록시 구성에 맞게 조정합니다. 환경 설정은 [SELECT AI 환경구성](SelectAiConfigure.md)에서 확인합니다.

Part 1 프로파일은 `annotations=false`로 설정하여 Annotation을 SQL 생성에 사용하지 않습니다. `ACCEPT LAB_OWNER`로 대상 테이블의 소유자를 입력받습니다. `LAB07` 또는 `SH`처럼 대문자로 입력하며, 접속 계정에는 해당 테이블의 조회 권한이 있어야 합니다.

```sql
DEFINE OLLAMA_ENDPOINT = http://service-ollama/v1
DEFINE OLLAMA_MODEL = gemma2:9b

ACCEPT LAB_OWNER CHAR PROMPT '테이블 소유자(대문자, 예: LAB00 또는 SH): '
SELECT USER AS current_user, '&&LAB_OWNER' AS target_owner FROM dual;


BEGIN
  -- 기존 프로파일 삭제: 없으면 무시
  DBMS_CLOUD_AI.DROP_PROFILE(
    profile_name => 'SELECTAI_PRODUCTS_NOANN',
    force        => TRUE
  );

  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'SELECTAI_PRODUCTS_NOANN',
    attributes   => '{
      "provider_endpoint": "&&OLLAMA_ENDPOINT",
      "model": "&&OLLAMA_MODEL",
      "object_list": [
        {"owner": "&&LAB_OWNER", "name": "PRODUCTS"},
        {"owner": "&&LAB_OWNER", "name": "SALES"},
        {"owner": "&&LAB_OWNER", "name": "COSTS"},
        {"owner": "&&LAB_OWNER", "name": "CUSTOMERS"},
        {"owner": "&&LAB_OWNER", "name": "COUNTRIES"},
        {"owner": "&&LAB_OWNER", "name": "TIMES"},
        {"owner": "&&LAB_OWNER", "name": "CHANNELS"},
        {"owner": "&&LAB_OWNER", "name": "PROMOTIONS"},
        {"owner": "&&LAB_OWNER", "name": "SUPPLEMENTARY_DEMOGRAPHICS"}
      ],
      "comments": false,
      "annotations": false,
      "constraints": true,
      "enforce_object_list": false,
      "conversation": false,
      "max_tokens": 1024,
      "temperature": 0,
      "seed": 42
    }',
    status      => 'enabled',
    description => 'Part 1: Annotation을 사용하지 않는 SH 단일 테이블 및 조인 실습'
  );
END;
/

EXEC DBMS_CLOUD_AI.SET_PROFILE('SELECTAI_PRODUCTS_NOANN');

SELECT DBMS_CLOUD_AI.GET_PROFILE() AS current_profile
FROM dual;
```

### SELECT AI 실행

#### runsql: SQL 실행 결과 조회

자연어 질문으로 생성한 SQL을 실행하여 조회 결과를 확인합니다.

```sql
EXEC DBMS_CLOUD_AI.SET_PROFILE('SELECTAI_PRODUCTS_NOANN');

-- 단일 테이블 질문
SELECT AI runsql 상품 대분류별 상품 수를 많은 순서로 보여줘;
SELECT AI runsql 야구용품 중 고가 상품의 상품명과 정가를 보여줘;

-- 조인 질문
SELECT AI runsql 연도별 야구용품 매출액을 보여줘;
SELECT AI runsql 국가별 고가 야구용품 매출액을 보여줘;
```

실행 결과 예시:

```text
SQL> SELECT AI runsql 상품 대분류별 상품 수를 많은 순서로 보여줘;

PROD_CATEGORY_DESC                                    상품 수
-------------------------------------------------- ----------
Cricket                                                    26
Baseball                                                   21
Tennis                                                     13
Soccer / Football                                          10
Golf                                                        2

SQL> SELECT AI runsql 야구용품 중 고가 상품의 상품명과 정가를 보여줘;

선택된 레코드가 없습니다.

SQL> SELECT AI runsql 연도별 야구용품 매출액을 보여줘;

선택된 레코드가 없습니다.

SQL> SELECT AI runsql 국가별 고가 야구용품 매출액을 보여줘;

선택된 레코드가 없습니다.
```

위 내용은 Annotation 미사용 상태에서 관찰한 실행 결과입니다. 조회 결과가 없더라도 실제 데이터가 없다는 뜻으로 단정하지 않습니다. 생성 SQL이 ‘야구용품’과 ‘고가 상품’의 업무 정의를 올바르게 반영했는지 확인하고, Part 2와 비교합니다.

## Part 2. Annotation을 사용하는 예제

테이블·컬럼에 업무 정의를 담은 Annotation을 추가하고, `annotations=true`인 별도 프로파일을 사용합니다. Part 1과 동일한 질문을 실행하여 **업무 의미를 보완한 Annotation이 SQL 작성의 정확도 향상에 어떤 도움을 주는지** 확인합니다.

### 프로파일 생성과 적용: SELECTAI_PRODUCTS_ANN

Part 2 프로파일은 `annotations=true`로 설정하여 [샘플 데이터 구성의 Annotation 등록](SampleDataConfig.md#2-실습-계정별-annotation-등록)에서 준비한 업무 정의와 조인 관계를 활용합니다. 엔드포인트·모델과 입력할 테이블 소유자는 Part 1과 동일하게 지정합니다.

```sql
DEFINE OLLAMA_ENDPOINT = http://service-ollama/v1
DEFINE OLLAMA_MODEL = gemma2:9b

ACCEPT LAB_OWNER CHAR PROMPT '테이블 소유자(대문자, 예: LAB00 또는 SH): '
SELECT USER AS current_user, '&&LAB_OWNER' AS target_owner FROM dual;


BEGIN
  -- 기존 프로파일 삭제: 없으면 무시
  DBMS_CLOUD_AI.DROP_PROFILE(
    profile_name => 'SELECTAI_PRODUCTS_ANN',
    force        => TRUE
  );

  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'SELECTAI_PRODUCTS_ANN',
    attributes   => '{
      "provider_endpoint": "&&OLLAMA_ENDPOINT",
      "model": "&&OLLAMA_MODEL",
      "object_list": [
        {"owner": "&&LAB_OWNER", "name": "PRODUCTS"},
        {"owner": "&&LAB_OWNER", "name": "SALES"},
        {"owner": "&&LAB_OWNER", "name": "COSTS"},
        {"owner": "&&LAB_OWNER", "name": "CUSTOMERS"},
        {"owner": "&&LAB_OWNER", "name": "COUNTRIES"},
        {"owner": "&&LAB_OWNER", "name": "TIMES"},
        {"owner": "&&LAB_OWNER", "name": "CHANNELS"},
        {"owner": "&&LAB_OWNER", "name": "PROMOTIONS"},
        {"owner": "&&LAB_OWNER", "name": "SUPPLEMENTARY_DEMOGRAPHICS"}
      ],
      "comments": false,
      "annotations": true,
      "constraints": true,
      "enforce_object_list": false,
      "conversation": false,
      "max_tokens": 1024,
      "temperature": 0,
      "seed": 42
    }',
    status      => 'enabled',
    description => 'Part 2: Annotation을 사용하는 SH 단일 테이블 및 조인 실습'
  );
END;
/

EXEC DBMS_CLOUD_AI.SET_PROFILE('SELECTAI_PRODUCTS_ANN');

SELECT DBMS_CLOUD_AI.GET_PROFILE() AS current_profile
FROM dual;
```

### SELECT AI 실행

#### runsql: SQL 실행 결과 조회

자연어 질문으로 생성한 SQL을 실행하여 조회 결과를 확인합니다.

```sql
EXEC DBMS_CLOUD_AI.SET_PROFILE('SELECTAI_PRODUCTS_ANN');

-- 단일 테이블 질문
SELECT AI runsql 상품 대분류별 상품 수를 많은 순서로 보여줘;
SELECT AI runsql 야구용품 중 고가 상품의 상품명과 정가를 보여줘;

-- 조인 질문
SELECT AI runsql 연도별 야구용품 매출액을 보여줘;
SELECT AI runsql 국가별 고가 야구용품 매출액을 보여줘;
```

실행 결과 예시:

```text
SQL> SELECT AI runsql 상품 대분류별 상품 수를 많은 순서로 보여줘;

PROD_CATEGORY_DESC                                    상품 수
-------------------------------------------------- ----------
Cricket                                                    26
Baseball                                                   21
Tennis                                                     13
Soccer / Football                                          10
Golf                                                        2

SQL> SELECT AI runsql 야구용품 중 고가 상품의 상품명과 정가를 보여줘;

PROD_NAME                                          PROD_LIST_PRICE
-------------------------------------------------- ---------------
Pitching Machine and Batting Cage Combo                     999.99
Speed Trainer Bats and Training Program                     899.99
Pro Maple Bat                                               192.99
5 Point Batting Tee                                         112.99
Pro Style Batting Tee                                       149.99

SQL> SELECT AI runsql 연도별 야구용품 매출액을 보여줘;

CALENDAR_YEAR 연도별 야구용품 매출액
------------- ----------------------
         2019             9073257.37
         2020             7766237.11
         2021             6464786.22
         2022             7859707.71

SQL> SELECT AI runsql 국가별 고가 야구용품 매출액을 보여줘;

COUNTRY_NAME                             Total_Sales
---------------------------------------- -----------
United States of America                  10380704.9
Germany                                   1710980.88
Japan                                     1485304.35
United Kingdom                            1257033.11
Italy                                         856885
Australia                                  724323.25
France                                     678509.15
Singapore                                  653413.03
Canada                                        557381
Spain                                      425063.59
Denmark                                    363374.78
Brazil                                      10089.87
Argentina                                    7097.72
Turkey                                       2647.24
China                                        1049.98
Poland                                        149.99
Saudi Arabia                                  149.99
New Zealand                                   149.99
```

## 비교 결과 해석

두 파트 모두 테이블·컬럼과 제약조건 정보를 활용하지만, **Part 1은 Annotation에 담긴 업무 정의를 사용하지 않고, Part 2는 이를 SQL 생성에 추가로 활용**합니다. Annotation은 데이터를 변경하는 것이 아니라 자연어 업무 용어를 실제 컬럼·값·조건·조인 관계에 연결하는 설명을 제공합니다.

| 질문 | Annotation 미사용: Part 1 | Annotation 사용: Part 2 | 비교 의미 |
|---|---|---|---|
| 상품 대분류별 상품 수 | 5개 분류의 상품 수 조회 | 동일한 5개 분류와 상품 수 조회 | 기본 집계는 Annotation 없이도 처리되었습니다. |
| 야구용품 중 고가 상품 | 조회 결과 없음 | 상품명과 정가 5건 조회 | 야구용품과 고가의 업무 정의를 제공한 효과를 비교합니다. |
| 연도별 야구용품 매출액 | 조회 결과 없음 | 2019~2022년 매출액 4건 조회 | 야구용품 값 매핑과 연도 기준, 상품·매출·시간 테이블의 조인을 비교합니다. |
| 국가별 고가 야구용품 매출액 | 조회 결과 없음 | 국가별 매출액 18건 조회 | 상품 조건과 고객의 국가 연결, 매출액 집계가 반영되는지 비교합니다. |

Annotation으로 **‘야구용품’은 `PROD_CATEGORY = 'Baseball'`, ‘고가 상품’은 `PROD_LIST_PRICE >= 100`**이라는 업무 의미를 제공합니다. 동일한 질문에 대해 Annotation 미사용 시에는 조회 결과가 없었지만, 사용 시에는 업무 조건에 해당하는 상품 5건이 조회되었습니다. 업무 용어와 실제 데이터 값·조건을 연결하는 Annotation이 **SQL 작성의 정확도 향상에 도움을 주는 사례**입니다.

위 내용은 확인된 실행 사례이며, 모델과 환경에 따라 생성 SQL과 결과는 달라질 수 있습니다. 각 Part에서 `showsql`로 생성 SQL도 확인하여 `Baseball` 조건과 정가 100 이상 조건이 반영되었는지 비교합니다. `showsql`은 별도로 SQL을 생성하므로, 앞서 실행한 `runsql`의 SQL과 동일하다고 가정하지 않습니다.

## SELECT AI 쿼리 정확도 향상 방안

Oracle은 **테이블·컬럼의 업무 설명과 관계 정보를 메타데이터로 제공**하여 자연어 질문에서 생성되는 SQL의 정확도를 높이는 방법을 안내합니다. 주요 방법은 다음과 같습니다. [Oracle SQL 생성 개선 가이드](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/generate-and-improve-sql-queries.html)

| 방법 | 적용 내용 |
|---|---|
| Comments 활용 | 테이블·컬럼의 용도와 업무 의미를 Comment로 작성하고 `comments=true`로 전달합니다. |
| Annotations 활용 | 업무 용어, 실제 데이터 값, 필터·집계 기준을 Annotation에 작성하고 `annotations=true`로 전달합니다. |
| PK·FK 관계 활용 | 실제 PK·FK 제약조건을 정의하고 `constraints=true`로 테이블 간 관계 정보를 전달하여 조인 조건 생성을 돕습니다. 옵션을 켜는 것만으로 제약조건이 생성되지는 않습니다. |

업무 설명에는 **단위·허용 값·시간 기준·조인 경로·동의어·예시 값** 등을 명확히 포함하는 것이 좋습니다. 이 실습에서는 ‘야구용품=Baseball’, ‘고가=정가 100 이상’, ‘매출액=AMOUNT_SOLD 합계’와 상품·고객·국가 테이블의 연결 관계가 해당합니다. [Oracle 메타데이터 보강 가이드](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/data-and-metadata-concepts.html)

본 실습은 Annotation의 효과를 비교하기 위해 두 Part 모두 `comments=false`를 유지합니다. 실제 활용에서는 필요한 메타데이터를 함께 제공하고, 생성 SQL의 조건·조인·집계를 검증합니다. 메타데이터 보강은 정확도 향상을 도울 수 있지만 모든 SQL의 정확성을 보장하지는 않습니다.
