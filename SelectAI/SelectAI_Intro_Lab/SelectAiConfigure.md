# SELECT AI 환경 구성

이 문서는 온프레미스에서 Select AI 실행을 위한 `DBMS_CLOUD` 패키지 설치, Wallet 구성, CDB·PDB ACL 설정을 다룹니다. 계정·역할·quota·SH 조회 및 패키지 실행 권한은 [실습 계정 관리](lab_admin.md)에서 준비합니다. 데이터 복사와 기본키·외래키 생성은 [실습 계정 관리](lab_admin.md#4-실습-계정별-데이터-준비), Annotation 등록은 [샘플 데이터 구성](SampleDataConfig.md)에서 진행합니다. Part별 프로파일은 [SELECT AI 예제](SelectAiExample.md)에서 생성합니다. `lab00`~`lab19` 계정과 SH의 전체 9개 테이블 및 데이터는 대상 PDB에 준비되어 있어야 합니다. PDB ACL 설정은 계정명을 입력하여 각 계정에 반복 적용합니다.

Shell 명령은 DB 서버의 Oracle 소프트웨어 소유 OS 계정에서, SQL은 SQL*Plus 또는 SQLcl에서 실행합니다. Oracle AI Database 26ai의 해당 설치 스크립트를 제공하는 RU 환경을 기준으로 합니다. 실습 PDB는 `orclpdb2`를 사용합니다. 테이블스페이스, Wallet 경로, Ollama 호스트·엔드포인트·모델은 실제 환경에 맞게 변경합니다. DB 서버에서 Ollama 호스트로 접속할 수 있어야 합니다.

| 설정 | 예시 값 | 설명 |
|---|---|---|
| 대상 PDB | `orclpdb2` | 실습 계정과 SH 전체 테이블이 있는 PDB |
| Wallet 경로 | `/home/oracle/wallets/ssl` | DB 서버의 Oracle OS 계정이 읽을 수 있는 자동 로그인 Wallet 디렉터리 |
| Ollama 호스트 | `service-ollama` | ACL에는 프로토콜·포트·경로를 제외한 호스트만 지정 |
| Ollama 엔드포인트 | `http://service-ollama/v1` | Ollama 프록시 구성 예시 주소. 실제 환경에 맞게 변경 |
| 모델 | `gemma2:9b` | DB 쿼리 실습용 예시 모델. 실제 Ollama에 설치된 모델명으로 변경 |

## 1. DBMS_CLOUD 패키지 설치

`DBMS_CLOUD` 계열 패키지는 `catclouduser.sql`로 서비스 계정을 준비하고, `dbms_cloud_install.sql`로 패키지를 설치합니다. `$ORACLE_HOME`과 `$ORACLE_SID`는 대상 DB의 환경으로 설정되어 있어야 합니다. `-u SYS`의 비밀번호 입력 요청에 응답하여 순서대로 실행합니다.

```bash
mkdir -p /tmp/selectai_install

"$ORACLE_HOME/perl/bin/perl" "$ORACLE_HOME/rdbms/admin/catcon.pl" \
  -u SYS -force_pdb_mode 'READ WRITE' \
  -b catclouduser_install -d "$ORACLE_HOME/rdbms/admin" \
  -l /tmp/selectai_install catclouduser.sql

"$ORACLE_HOME/perl/bin/perl" "$ORACLE_HOME/rdbms/admin/catcon.pl" \
  -u SYS -force_pdb_mode 'READ WRITE' \
  -b dbms_cloud_install -d "$ORACLE_HOME/rdbms/admin" \
  -l /tmp/selectai_install dbms_cloud_install.sql
```

`/tmp/selectai_install`의 설치 로그를 확인합니다. 설치 과정은 PDB를 `READ WRITE`로 열어 작업한 후 원래 상태로 복구하므로, 대상 PDB가 열려 있는 상태에서 아래 확인을 수행합니다. 이미 설치된 환경은 먼저 상태를 확인하고, 재설치 시 기존 계정·객체가 있다는 메시지와 실제 설치 오류를 구분합니다.

SYS로 접속한 뒤 CDB와 대상 PDB에서 `DBMS_CLOUD`, `DBMS_CLOUD_AI`의 패키지·본문이 존재하고 `VALID`인지 확인합니다.

```bash
sqlplus / as sysdba
```

```sql
DEFINE LAB_PDB = orclpdb2

ALTER SESSION SET CONTAINER = CDB$ROOT;

SELECT con_id, owner, object_name, object_type, status
FROM   cdb_objects
WHERE  owner = 'C##CLOUD$SERVICE'
AND    object_name IN ('DBMS_CLOUD', 'DBMS_CLOUD_AI')
AND    object_type IN ('PACKAGE', 'PACKAGE BODY')
ORDER BY con_id, object_name, object_type;

ALTER SESSION SET CONTAINER = &&LAB_PDB;

SELECT owner, object_name, object_type, status
FROM   dba_objects
WHERE  owner = 'C##CLOUD$SERVICE'
AND    object_name IN ('DBMS_CLOUD', 'DBMS_CLOUD_AI')
AND    object_type IN ('PACKAGE', 'PACKAGE BODY')
ORDER BY object_name, object_type;
```

참고: [Oracle DBMS_CLOUD 설치 안내](https://docs.oracle.com/en/database/oracle/oracle-database/26/sutil/installing-dbms_cloud.html)

## 2. Wallet 구성

이 실습의 온프레미스 환경에서는 HTTP Ollama 연결에서도 내부 처리 과정에서 `SSL_WALLET` 설정을 확인하므로 Wallet을 준비합니다. 이 설정이 없으면 `ORA-20000: Database property SSL_WALLET not found`가 발생할 수 있습니다. Wallet은 Ollama API의 사용자 인증 정보와는 별개입니다.

### 2.1 Oracle OS 계정: 자동 로그인 Wallet 생성

`<WALLET_PASSWORD>`를 사용할 Wallet 비밀번호로 변경합니다. 기존 Wallet이 있으면 새로 만들지 않고 해당 Wallet을 사용합니다.

```bash
mkdir -p /home/oracle/wallets/ssl
chmod 700 /home/oracle/wallets/ssl

"$ORACLE_HOME/bin/orapki" wallet create \
  -wallet /home/oracle/wallets/ssl \
  -auto_login -pwd '<WALLET_PASSWORD>'

"$ORACLE_HOME/bin/orapki" wallet display \
  -wallet /home/oracle/wallets/ssl

ls -l /home/oracle/wallets/ssl/ewallet.p12 \
      /home/oracle/wallets/ssl/cwallet.sso
```

현재 예시의 HTTP 엔드포인트는 TLS 인증서를 사용하지 않습니다. HTTPS 엔드포인트를 사용할 때는 서버 인증서 체인을 검증할 신뢰 인증서도 Wallet에 등록합니다. RAC 환경에서는 모든 DB 노드에서 Wallet 경로와 파일을 사용할 수 있어야 합니다.

### 2.2 SYS: SSL_WALLET 설정과 확인

`SSL_WALLET`은 `CDB$ROOT`에서 설정합니다. 이미 설정되어 있으면 현재 경로를 먼저 조회하고, 기존 서비스를 고려하여 사용할 경로를 결정합니다.

```sql
ALTER SESSION SET CONTAINER = CDB$ROOT;

SELECT property_name, property_value
FROM   database_properties
WHERE  property_name = 'SSL_WALLET';

-- 실제 사용할 Wallet 디렉터리로 설정
ALTER DATABASE PROPERTY SET SSL_WALLET = '/home/oracle/wallets/ssl';

-- 설정 후 경로 확인
SELECT property_name, property_value
FROM   database_properties
WHERE  property_name = 'SSL_WALLET';
```

참고: [Oracle SSL Wallet 구성 안내](https://docs.oracle.com/en/database/oracle/oracle-database/26/sutil/create-ssl-wallet-with-certificates.html)

## 3. 관리자: CDB·PDB ACL 등록

SYS 등 CDB·PDB를 관리할 수 있는 계정으로 실행합니다. CDB에서는 패키지 소유 계정 `C##CLOUD$SERVICE`, 대상 PDB에서는 입력한 실습 계정의 ACL을 등록합니다. 각 계정에 HTTP 호출과 네트워크 접근 권한을 지정하고, 해당 컨테이너에서 등록 결과를 확인합니다.

| 실행 위치 | ACL 대상 계정 | 예시 권한 |
|---|---|---|
| `CDB$ROOT` | `C##CLOUD$SERVICE` | `http`, `connect`, `resolve` |
| 대상 PDB | 입력한 실습 계정(`LAB_USER`) | `http`, `connect`, `resolve` |

호스트는 프로토콜·포트·`/v1` 경로를 제외한 이름으로 지정합니다. 아래는 포트 제한 없이 지정 호스트에 등록하는 예시입니다. `http_proxy`는 인터넷 접속용 HTTP 프록시를 사용할 때 별도로 검토하며, 현재 Ollama 역방향 프록시 예시에는 지정하지 않습니다.

```sql
DEFINE LAB_PDB = orclpdb2
DEFINE OLLAMA_HOST = service-ollama
ACCEPT LAB_USER CHAR DEFAULT 'lab00' PROMPT '설정할 실습 계정(lab00~lab19, 기본 lab00): '

WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
BEGIN
  IF NOT REGEXP_LIKE(UPPER('&&LAB_USER'), '^LAB(0[0-9]|1[0-9])$') THEN
    RAISE_APPLICATION_ERROR(-20001, '실습 계정은 lab00~lab19 중 하나를 입력하십시오.');
  END IF;
END;
/

-- CDB: Cloud 패키지 서비스 계정 ACL
ALTER SESSION SET CONTAINER = CDB$ROOT;

BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => '&&OLLAMA_HOST',
    ace  => xs$ace_type(
      privilege_list => xs$name_list('http', 'connect', 'resolve'),
      principal_name => 'C##CLOUD$SERVICE',
      principal_type => xs_acl.ptype_db
    )
  );
END;
/

-- CDB의 서비스 계정 ACL 확인
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS current_container
FROM dual;

SELECT host, lower_port, upper_port, principal, privilege, grant_type
FROM   dba_host_aces
WHERE  host = '&&OLLAMA_HOST'
AND    principal = 'C##CLOUD$SERVICE'
ORDER BY privilege;

-- PDB: 입력한 실습 계정에서 Ollama 서비스에 접근할 수 있도록 등록
ALTER SESSION SET CONTAINER = &&LAB_PDB;
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => '&&OLLAMA_HOST',
    ace  => xs$ace_type(
      privilege_list => xs$name_list('http', 'connect', 'resolve'),
      principal_name => UPPER('&&LAB_USER'),
      principal_type => xs_acl.ptype_db
    )
  );
END;
/

-- 대상 PDB의 ACL 등록 확인
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS current_container
FROM dual;

SELECT host, lower_port, upper_port, principal, privilege, grant_type
FROM   dba_host_aces
WHERE  host = '&&OLLAMA_HOST'
AND    principal = UPPER('&&LAB_USER')
ORDER BY privilege;

WHENEVER SQLERROR CONTINUE NONE
```

각 ACL 확인 결과에서 대상 호스트·대상 계정의 `http`, `connect`, `resolve`가 `GRANT`로 등록되어 있는지 확인합니다.

참고: [Oracle DBMS_CLOUD 서비스 계정 ACE 구성](https://docs.oracle.com/en/database/oracle/oracle-database/26/sutil/configure-dateabase-aces-for-dbms_cloud.html), [사용자 ACE 구성](https://docs.oracle.com/en/database/oracle/oracle-database/26/sutil/configure-aces-user-role-use-dbms_cloud.html)

환경 구성이 끝나면 [실습 계정 관리](lab_admin.md)에서 패키지 실행 권한과 데이터를 준비한 뒤, [샘플 데이터 구성](SampleDataConfig.md)에서 Annotation을 등록합니다.
