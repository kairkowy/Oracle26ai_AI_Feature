> 로컬 실습 환경 구성 기록입니다. 현재 저장소의 실행 전제와 경로는 [공통 준비 문서](00.Setup.md)를 먼저 확인합니다. 설치 버전·호스트·계정은 사용 환경에 맞게 변경하고, Jupyter 비밀번호 해시는 직접 생성합니다.

오라클 - Ollama 환경 RAG 예제 시나리오 참고 자료

1. 환경
- 클라이언트
  - oracle instance client 2.0.1
  - jupyter notebook
  - python 3.12.8
  - pip 25.0.1
  - library : oml
  - oml4py client
- DBMS
  - oracle23.7
  - oml4py server
- AI Platform
  - Ollama
- Model
  - LLM : llama3.2
  - 임베딩 : jeffh/intfloat-multilingual-e5-large-instruct:f16

2. jupyter 및 PIP 설치 : 세부내용은 인터넷 참고

Jupyter 다운로드 & 설치

jupyter 패스워드 암호와 생성

```shell
[dev01@localhost .jupyter]$ ipython
Python 3.12.9 (main, Mar 26 2025, 10:43:27) [GCC 8.5.0 20210514 (Red Hat 8.5.0-24.0.1)]
Type 'copyright', 'credits' or 'license' for more information
IPython 9.0.2 -- An enhanced Interactive Python. Type '?' for help.
Tip: You can find how to type a latex symbol by back completing it `\θ<tab>` will expand to `\theta`.

In [1]: from jupyter_server.auth import passwd

In [2]: passwd()
Enter password:
Verify password:
Out[2]: '<passwd()로 생성한 해시>'

# Out) 복사해서 jupyter config에 복제 사용

# 입력한 패스워드 기억해 둠(브라우저 로그인 화면에서 패스워드 입력 필요함)

```

jupyter lab 구성(외부 접속, 패스워드 등)
```shell
cd /home/dev01/.jupyter

jupyter lab --generate-config

vi jupyter_lab_config.py
#---------- vi
c.LabServerApp.config_file_name = 'jupyter_lab_config.py'

#외부접속 허용
c.ServerApp.allow_origin = '*'

#작업경로 설정
c.ServerApp.notebook_dir = '/home/dev01/labs/'

#아이피 설정 -  외부 접속 허용(listen)
c.ServerApp.ip = '0.0.0.0'

#포트 설정
# OCI경우 8888 포트 차단됨
c.ServerApp.port = 7100

# 비밀번호 암호키 설정 for after 2.x
# 챂에서 만든 패스워드 암호화 값 사용
c.PasswordIdentityProvider.hashed_password = '<passwd()로 생성한 해시>'
c.ServerApp.token = ''

#------------ end vi
```
jupyter lab 실행

```shell
nohup jupyter lab --config /home/dev01/.jupyter/jupyter_lab_config.py &
```

jupyter lab 실행 검증

```
# Jupyter가 떠있는지
ps -ef | grep jupyter

dev01       8619       1  0 00:07 pts/0    00:00:02 /home/dev01/python/Python-3.12.6/bin/python3 /home/dev01/python/Python-3.12.6/bin/jupyter-lab --config /home/dev01/.jupyter/jupyter_lab_config.py

# 어떤 IP/포트에 바인드됐는지
ss -lntp | grep 7100
LISTEN 0      128          0.0.0.0:7100       0.0.0.0:*    users:(("jupyter-lab",pid=7188,fd=6))

# 로컬에서 응답되는지
curl -I http://127.0.0.1:7100/lab

HTTP/1.1 405 Method Not Allowed     -- 정상적임
Server: TornadoServer/6.5.2
Content-Type: text/html
Date: Fri, 07 Nov 2025 00:16:04 GMT
X-Content-Type-Options: nosniff
Content-Security-Policy: frame-ancestors 'self'; report-uri /api/security/csp-report
Content-Length: 2921
Set-Cookie: _xsrf=2|dd9f335d|06b553f578fe9b90b1f5d21f38ebeac1|1762474564; Path=/

```

OCI 포트 개방 - Add ingress rule

```
security rules에 추가
source CIDR : 0.0.0.0/0
IP protocol : TCP
Source port range : All
Destination port Range : 7100
```

* Firewall port 개방 또는 Firewall Disable


3. ollama 구성 : 세부 내용은 인터넷 참고

ollama 다운로드

```shell
curl -fsSL https://ollama.com/install.sh | sh
```

ollama 서비스 수정(외부에서 접속 가능한 서비스 실행)

```config
sudo vi /etc/systemd/system/ollama.service
#-----------------vi
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/home/dev01/python/Python-3.12.9/bin:/home/dev01/oracle/instantclient_23_7:/usr/bin"
Environment="OLLAMA_HOST=0.0.0.0"
User=root

[Install]
#WantedBy=default.target
WantedBy=multi-user.target

#------------ end of vi
```

ollama 서비스 시작

```shell
sudo systemctl daemon-reload
sudo systemctl start ollama
sudo systemctl enable ollama

firewall port(11434) 개방
```

OCI 포트 개방 - Add ingress rule

```
security rules에 추가
source CIDR : 0.0.0.0/0
IP protocol : TCP
Source port range : All
Destination port Range : 11434
```

* Firewall port 개방 또는 Firewall Disable


model 다운로드 및 레포지토리 저장

```shell
ollama run llama3.2
ollama run jeffh/intfloat-multilingual-e5-large-instruct:f16
ollama ls
```

Ollama 서비스(임베딩) 확인

```shell
curl -X POST http://192.168.100.7:11434/api/embeddings -d '{"model" : "jeffh/intfloat-multilingual-e5-large-instruct:f16","prompt": "군인공제회 소개해주세요", "stream" : false}'

curl -X POST http://localhost:11434/api/generate -d '{"model" : "llama3.2","prompt": "군인공제회 소개해주세요","stream" : false}'
```

4. DB 환경 준비

- DB 설치 : 233ai free 버전 다운로드

- 23ai free 설치 :

5. 클라이언트 환경 준비

Oracle Instance client 설치

   - OML for python 2-23ai 사용자 가이드 참고(4.5.1.1 Install Oracle Instant Client and the OML4Py Client for Linux)
     https://docs.oracle.com/en/database/oracle/machine-learning/oml4py/2-23ai/mlpug/install-oracle-instant-client-linux-premises-databases.html

OML4PY client 설치
   - OML for python 2-23ai 사용자 가이드 참고(4.5.1.2 Install OML4Py Client for Linux for On-Premises Databases)
     https://docs.oracle.com/en/database/oracle/machine-learning/oml4py/2-23ai/mlpug/install-oml4py-client-linux-premises-databases.html

PIP library 설치

vi requirements.txt

```vi
--extra-index-url https://download.pytorch.org/whl/cpu
pandas==2.2.2
setuptools==70.0.0
scipy==1.14.0
matplotlib==3.8.4
oracledb==2.4.1
scikit-learn==1.5.1
numpy==2.0.1
onnxruntime==1.20.0
onnxruntime-extensions==0.12.0
onnx==1.17.0
torch==2.6.0
transformers==4.49.0
sentencepiece==0.2.0

```

python3 -m pip install -r requirements.txt


DB 계정 준비
  - 계정명: vector
  - Role : DB_DEVELOPER_ROLE, create credential, execute on SYS.UTL_HTTP, execute on sys.dbms_network_acl_admin

계정 생성

```sql
CREATE USER vector identified by vector;
ALTER USER vector QUOTA UNLIMITED ON users;

GRANT DB_DEVELOPER_ROLE, create credential to vector;
GRANT execute on SYS.UTL_HTTP to vector

GRANT execute on sys.dbms_network_acl_admin to vector;
```

OLLAMA - 오라클 연결 및 테스트

```sql
sqlplus vector/vector@freepdb1

# ACL 생성
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => '*',
    ace => xs$ace_type(privilege_list => xs$name_list('connect'),
                       principal_name => 'vector',
                       principal_type => xs_acl.ptype_db));
END;
/
# 오라클 유틸리티 이용한 임베딩 테스트

var embed_ollama_params clob;
exec :embed_ollama_params := '{"provider": "ollama","host":"local","url": "http://180.68.194.221:11434/api/embeddings","model":"llama3.2"}';

select dbms_vector.utl_to_embedding('국방동원정보체계 보안강화 사업', json(:embed_ollama_params)) ollama_output;  -- 임베딩 쿼리

OLLAMA_OUTPUT
--------------------------------------------------------------------------------
[-2.1026895E+000,1.87008286E+000,-8.44160765E-002,-1.41829121E+000,


var gent_ollama_params clob;
exec :gent_ollama_params := '{"provider": "ollama","host":"local","url": "http://localhost:11434/api/generate","model":"llama3.2"}';

select dbms_vector.utl_to_generate_text('군인공제회 소개해주세요', json(:gent_ollama_params)) ollama_output;  -- 질문 쿼리

OLLAMA_OUTPUT
--------------------------------------------------------------------------------
군인공제회는 한국의 군인과 민간人が 함께하는 단체입니다

```

5. 데모 데이터 준비

테이블 생성 : XF_DOC

```sql
CREATE TABLE IF NOT EXISTS XF_DOC(
DOC_ID VARCHAR2(34),
YEAR VARCHAR2(4),
EXECUTE_DATE CHAR(14),
DOC_NUM_ST VARCHAR2(300),
TITLE VARCHAR2(400), DRAFTER_ID VARCHAR2(40),
DRAFTER_NAME VARCHAR2(30),
CASTING_VOTER_ID VARCHAR2(40),
CASTING_VOTER_NAME VARCHAR2(40),
OWN_DEPT_CODE CHAR(7),
OWN_DEPT_NAME VARCHAR2(300),
VECTOR_SOURCE VECTOR,
PRIMARY KEY(DOC_ID));
```

데이터 로딩 : sqlloader 사용

  - control 파일 생성

```text

options (skip=1)
load data
infile './data/doc/xf_doc.csv'
  into table xf_doc
  fields terminated by ','
  (
  DOC_ID CHAR(34),
  YEAR CHAR(4),
  EXECUTE_DATE CHAR,
  DOC_NUM_ST CHAR,
  TITLE CHAR,
  DRAFTER_ID CHAR,
  DRAFTER_NAME CHAR,
  CASTING_VOTER_ID CHAR,
  CASTING_VOTER_NAME CHAR,
  OWN_DEPT_CODE CHAR,
  OWN_DEPT_NAME CHAR,
  );
```

  - sqlloader 실행

```shell
sqlldr vector/vector@freepdb1 control=xf_doc.ctl

```
  - 테이블 정보 확인
``` sql

analyze table xf_doc compute statistics;

select table_name, num_rows, blocks from user_tables where table_name = 'XF_DOC';

TABLE_NAME                       NUM_ROWS     BLOCKS
------------------------------ ---------- ----------
XF_DOC                                285         13


select a.table_name, b.bytes/1048576 MB from user_tab_columns a, user_segments b
where a.table_name = b.segment_name and a.table_name = 'XF_DOC'
and a.data_type = 'VECTOR'

TABLE_NAME                             MB
------------------------------ ----------
XF_DOC                               .125

```
