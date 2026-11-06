# SELECT AI 예제

## 예제 개요

이 예제는 **Annotation을 활용하여 자연어 질문에서 생성되는 SQL의 정확도를 높이는 방법**을 실습합니다. Annotation에 테이블·컬럼의 업무 의미와 해석에 필요한 정보를 제공하고, 적용 전후의 생성 SQL과 조회 결과를 비교합니다.

| 항목 | 내용 |
|---|---|
| 실습 데이터 | Oracle 샘플 `SH`(Sales History) 스키마의 전체 9개 테이블을 `LAB00`에 복사한 데이터 |
| 실습 계정 | `lab00` |
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

[SELECT AI 실습환경 구성](SelectAiConfigure.md)의 관리자 설정과 [샘플 데이터 구성](SampleDataConfig.md)의 데이터·Annotation 준비를 먼저 완료합니다. 이후 스크립트는 SQL*Plus 또는 SQLcl에서 **대상 PDB에 `lab00`으로 접속한 세션**에서 실행합니다. Part 1은 등록된 Annotation을 사용하지 않고, Part 2는 같은 Annotation을 사용합니다.

### ACL 확인

Ollama 호스트는 구성 문서에서 등록한 값과 동일하게 지정합니다. `USER_HOST_ACES`에서 현재 계정의 호스트 접근 권한을 확인합니다. CDB의 서비스 계정 ACL은 구성 문서에 따라 관리자가 확인합니다.

```sql
DEFINE OLLAMA_HOST = service-ollama

SELECT host, lower_port, upper_port, privilege
FROM   user_host_aces
WHERE  host = '&&OLLAMA_HOST'
ORDER BY privilege;
```

예시 구성에서는 `http`, `connect`, `resolve` 권한이 표시되어야 합니다. 이 조회는 ACL 확인이며, 실제 Ollama 서비스의 실행 상태와 모델 응답까지 확인하는 것은 아닙니다.

### 데이터 확인

실습 대상은 SH의 전체 9개 테이블을 `LAB00`에 복사한 데이터입니다. 모든 테이블에 데이터가 준비되었는지 확인하고, 상품의 주요 컬럼 값도 조회합니다.

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

Ollama 엔드포인트와 모델명을 실제 환경에 맞게 변경합니다. 인증 없는 Ollama 프록시 구성이므로 `credential_name`은 지정하지 않습니다. `/v1` 경로는 [참조 문서](../SelectAI/SelectAI_Config_Run.md)의 23.26.2 구성을 기준으로 하며, 설치 버전과 프록시 구성에 맞게 조정합니다.

Part 1 프로파일은 `annotations=false`로 설정하여 Annotation을 SQL 생성에 사용하지 않습니다.

```sql
DEFINE OLLAMA_ENDPOINT = http://service-ollama/v1
DEFINE OLLAMA_MODEL = gemma2:9b

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
        {"owner": "LAB00", "name": "PRODUCTS"},
        {"owner": "LAB00", "name": "SALES"},
        {"owner": "LAB00", "name": "COSTS"},
        {"owner": "LAB00", "name": "CUSTOMERS"},
        {"owner": "LAB00", "name": "COUNTRIES"},
        {"owner": "LAB00", "name": "TIMES"},
        {"owner": "LAB00", "name": "CHANNELS"},
        {"owner": "LAB00", "name": "PROMOTIONS"},
        {"owner": "LAB00", "name": "SUPPLEMENTARY_DEMOGRAPHICS"}
      ],
      "comments": false,
      "annotations": false,
      "constraints": true,
      "enforce_object_list": true,
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

#### narrate: 조회 결과의 자연어 설명

SQL 조회 결과를 LLM에 전달하여 자연어 설명을 받습니다.

```sql
EXEC DBMS_CLOUD_AI.SET_PROFILE('SELECTAI_PRODUCTS_NOANN');

-- 단일 테이블 질문
SELECT AI narrate 상품 대분류별 상품 수를 많은 순서로 보여줘;
SELECT AI narrate 야구용품 중 고가 상품의 상품명과 정가를 보여줘;

-- 조인 질문
SELECT AI narrate 연도별 야구용품 매출액을 보여줘;
SELECT AI narrate 국가별 고가 야구용품 매출액을 보여줘;
```

## Part 2. Annotation을 사용하는 예제

테이블·컬럼에 업무 정의를 담은 Annotation을 추가하고, `annotations=true`인 별도 프로파일을 사용합니다. Part 1과 동일한 질문을 실행하여 **업무 의미를 보완한 Annotation이 SQL 작성의 정확도 향상에 어떤 도움을 주는지** 확인합니다.

### 프로파일 생성과 적용: SELECTAI_PRODUCTS_ANN

Part 2 프로파일은 `annotations=true`로 설정하여 [샘플 데이터 구성의 Annotation 등록](SampleDataConfig.md#3-lab00-annotation-등록)에서 준비한 업무 정의와 조인 관계를 활용합니다. 엔드포인트와 모델은 Part 1과 동일하게 지정합니다.

```sql
DEFINE OLLAMA_ENDPOINT = http://service-ollama/v1
DEFINE OLLAMA_MODEL = gemma2:9b

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
        {"owner": "LAB00", "name": "PRODUCTS"},
        {"owner": "LAB00", "name": "SALES"},
        {"owner": "LAB00", "name": "COSTS"},
        {"owner": "LAB00", "name": "CUSTOMERS"},
        {"owner": "LAB00", "name": "COUNTRIES"},
        {"owner": "LAB00", "name": "TIMES"},
        {"owner": "LAB00", "name": "CHANNELS"},
        {"owner": "LAB00", "name": "PROMOTIONS"},
        {"owner": "LAB00", "name": "SUPPLEMENTARY_DEMOGRAPHICS"}
      ],
      "comments": false,
      "annotations": true,
      "constraints": true,
      "enforce_object_list": true,
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

#### narrate: 조회 결과의 자연어 설명

SQL 조회 결과를 LLM에 전달하여 자연어 설명을 받습니다.

```sql
EXEC DBMS_CLOUD_AI.SET_PROFILE('SELECTAI_PRODUCTS_ANN');

-- 단일 테이블 질문
SELECT AI narrate 상품 대분류별 상품 수를 많은 순서로 보여줘;
SELECT AI narrate 야구용품 중 고가 상품의 상품명과 정가를 보여줘;

-- 조인 질문
SELECT AI narrate 연도별 야구용품 매출액을 보여줘;
SELECT AI narrate 국가별 고가 야구용품 매출액을 보여줘;
```

프로파일 이름과 `annotations` 값을 제외한 LLM·대상 객체·처리 옵션은 두 파트에서 동일하게 유지합니다. `comments=false`와 `conversation=false`도 유지하여 Comment와 이전 대화의 영향을 줄입니다. `comments`와 `annotations`는 각각 별도 옵션입니다. [Oracle 공식 문서](https://docs.oracle.com/en/database/oracle/oracle-database/26/selai/generate-and-improve-sql-queries.html)

프로파일 생성 구문은 해당 Part의 기존 프로파일을 먼저 삭제한 후 다시 생성합니다. `force => TRUE`는 프로파일이 없어도 삭제 단계에서 오류가 발생하지 않도록 합니다. 새 DB 세션으로 접속할 때는 해당 Part의 `SET_PROFILE`을 다시 실행합니다.

생성 SQL은 기대 SQL 및 조회 결과와 함께 검증합니다.
