# SELECT AI 실습환경 구성

이 문서는 SELECT AI 예제 실행 전 관리자가 수행할 권한·ACL 설정과 lab00의 데이터 준비를 다룹니다. Part별 프로파일은 [SELECT AI 예제](SelectAiExample.md)에서 생성합니다. `DBMS_CLOUD`·`DBMS_CLOUD_AI` 패키지 설치와 Wallet 구성은 [온프레미스 Select AI 구성 문서](../SelectAI/SelectAI_Config_Run.md)를 참고하여 먼저 완료합니다. `lab00` 계정과 `SH.PRODUCTS` 데이터도 대상 PDB에 준비되어 있어야 합니다.

아래 SQL은 SQL*Plus 또는 SQLcl 기준입니다. PDB 이름, 테이블스페이스, Ollama 호스트·엔드포인트·모델은 실제 환경에 맞게 변경합니다. DB 서버에서 Ollama 호스트로 접속할 수 있어야 합니다.

| 설정 | 예시 값 | 설명 |
|---|---|---|
| 대상 PDB | `orclpdb1` | `lab00`과 `SH.PRODUCTS`가 있는 PDB |
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
GRANT SELECT ON SH.PRODUCTS TO lab00;

ALTER USER lab00 QUOTA 20M ON &&LAB_TABLESPACE;

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

이후 스크립트는 **대상 PDB에 `lab00`으로 접속한 세션**에서 실행합니다. Annotation을 직접 추가할 수 있도록 원본 데이터를 `LAB00.PRODUCTS`로 복사합니다. 원본 `SH.PRODUCTS`는 수정하지 않습니다. 이 단계는 최초 준비 시 한 번 실행합니다.

```sql
DEFINE LAB_TABLESPACE = USERS

CREATE TABLE products TABLESPACE &&LAB_TABLESPACE AS
SELECT * FROM sh.products;

ALTER TABLE products
  ADD CONSTRAINT lab00_products_pk PRIMARY KEY (prod_id);

SELECT COUNT(*) AS product_count FROM products;
```

환경 구성이 끝나면 [SELECT AI 예제의 실행 전 확인](SelectAiExample.md#실행-전-확인)으로 이동합니다.
