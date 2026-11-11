## Oracle 벡터 검색 환경 설정을 위한 오프라인 서버 작업 가이드

오프라인(인터넷 액세스 불가) 환경에서 오라클 벡터검색 환경구성을 위한 가이드 문서입니다. 오라클 사용자 가이드 매뉴얼 내용은 인터넷 온라인 환경을 기준으로 기술되어 있어서 오프라인 환경의 작업을 위해서는 개별적인 추가 작업 기술이 필요합니다. 이러한 부분에서 온라인, 오프라인 작업자의 작업을 돕기 위하여 관련 내용을 정리하게 되었습니다.

### 1. Oracle Linux(8.10) 설치

오프라인 환경에 온라인에서 다운로드한 파일을 이동해서 가상환경의 미디어 환경에 마운트시킵니다.

VMware 가상머신에서 마운트 된 ISO file을 이용하여 OL8.10을 설치하는 방법 https://github.com/kairkowy/handon-labs-for-vector-search/blob/main/similarity_search/VMware%20%EA%B0%80%EC%83%81%EB%A8%B8%EC%8B%A0%EC%97%90%EC%84%9C%20ISO%20file%20for%20OL8.10%EC%9D%84%20%EC%84%A4%EC%B9%98%ED%95%98%EB%8A%94%20%EB%B0%A9%EB%B2%95.md 을 참고하여 OS를 설치합니다.


### 2. 오라클 Instant Client for linux 설치 

2.1 필수 라이브러리(libaio) 설치

온라인에서 다운로드 한 파일을 오프라인 서버로 이동했으면 오프라인 설치를 위하여 다음과 같이 진행합니다.

```
su - root
mkdir -p /opt/oracle
cp /tmp/libaio_rpms.tar /opt/oracle 
chown -R dedadmin:orausers /opt/oracle
cd /opt/oracle
tar xvf libaio_rpms.tar
cd /opt/oracle/libaio_rpms
ls
# 파일 리스트 확인

libaio-0.3.112-1.el8.x86_64.rpm  
libaio-devel-0.3.112-1.el8.x86_64.rpm

rpm -Uvh /opt/oracle/libaio_rpms/*.rmp
rpm -qa|grep libaio
```

2.2 Oracle Instant client 공통 환경 설치(오프라인 서버)

- 공통 환경 서버 : 오프라인 서버 Oracle Linux 8.10
- OS계정 : oracle 
- 계정 그룹 : orausers
- 오라클 인스턴트 클라이언트 버전 : 23.26(Linux)
- 위치 : /opt/oracle/instantclient_23_26
- tnsnames.ora 위치: /opt/oracle/instantclient_23_26/network/admin

온라인 서버에서 다운로드 한 파일들을 오프라인 서버로 이동했으면 오프라인 서버에서 다음과 같이 진행합니다.

```
# 설치 파일 복사
su - orale
cp /tmp/instantclient*.zip /opt/oracle
cd /opt/oracle

# 설치파일 압축 풀기

unzip instantclient-basic-linux.x64-23.26.0.0.0.zip

unzip instantclient-sqlplus-linux.x64-23.26.0.0.0.zip  
-> A

unzip instantclient-tools-linux.x64-23.26.0.0.0.zip  
-> A
```

2.3 라이브러리 링크 생성

```
# /opt/oracle/instantclient_23_26 디렉토리 및 파일 확인

su - root
$ sh -c "echo /opt/oracle/instantclient_23_26 > /etc/ld.so.conf.d/oracle-instantclient.conf"
$ ldconfig
```

2.4 유저 환경 설정  

오라클 클라이언트 환경이 필요한 계정에서 다음과 같이 진행합니다.

```
su - root
useradd -g orausers 계정명
passwd 계정명

su - 계정명

vi .bash_profile
export ORACLE_HOME=/opt/oracle/instantclient_23_26
export LD_LIBRARY_PATH=$ORACLE_HOME:$LD_LIBRARY_HOME
export PATH=$ORACLE_HOME:$PATH

source .bash_profile
```
tnsnames.ora 파일 등록 또는 업데이트

```
su - oracle

cd $ORACLE_HOME/network/admin

tee $ORACLE_HOME/network/admin/tnsnames.ora<<EOF

dwa = .....

EOF
```

DB 접속 테스트

sqlplus labadmin/labadmin@xdwa

DB접속이 정상적으로 되는지 확인 합니다.


### 3. 파이썬 설치

3.1 오라클 백터검색 유틸리티 셋

- 파이썬 3.12.6 소스 파일 : /opt/python/Python-3.12.6.tgz
- pip 업그레이드 파일 : /opt/python/pip_offline/pip-25.3-py3-none-any.whl
- 오라클 벡터검색 기본 라이브러리(PIP wheels) : /opt/python/def_whl
- oml4py 라이브러리(PIP wheel) : /opt/oracle/oml4py/client/oml-2.1-cp312-cp312-linux_x86_64.whl
- jupyterlab 설치 소스 파일 : /opt/python/jupyterlab_wheelhouse

3.2 필수 라이브러리 설치 

온라인 서버에서 필수 라이브러리 셋을 오프라인 서버로 이동했으면 다음과 같이 진행합니다.

```
su - root

mkdir -p /opt/python

cp /tmp/python_rpms_no_tk.tar /opt/python/.  
cd /opt/python
tar xvf python_rpms_no_tk.tar 
cd /opt/python/python_rpms_no_tk

dnf --disablerepo="*" --nogpgcheck install ./*.rpm
```

3.3 sqlite 확인 및 설치

```
python -c "import sqlite3"

ModuleNotFoundError: No module named '_sqlite3' 에러 발생시 sqlite3-devel 설치 후 python 부터 재설치를 진행하세요. 

rpm -q sqlite sqlite-libs sqlite-devel
```
sqlite-devel 패키지가 없으면 sqlite3 설치합니다. 온라인 서버에서 다운로드한 sqlite3 패키지를 오프라인 서버로 이동했으면 다음과 같이 진행합니다.

```
su - root

cd /tmp
tar xvf sqlite_rpms.tar

cd sqlite_rpms
dnf --disablerepo="*" --nogpgcheck localinstall -y ./*.rpm
rpm -q sqlite sqlite-libs sqlite-devel
sqlite3 --version
```

3.4 파이썬 빌드

파이썬은 개별 계정별로 설치하는 방법을 제안드립니다. AI 모델 특성상 버전 호환성이 민감하여 개정별로 패키지 버전 관리가 유용합니다.
오프라인 서버로 python-3.12.6.tgz 파일을 이동했으면 다음을 진행합니다.

설치 소스 파일 준비

```
su - 계정명
mkdir -p $HOME/python
cp /opt/python/Python-3.12.6.tgz $HOME/python/.
cd $HOME/python
tar xvf Python-3.12.6.tgz 
```
파이썬 빌드 및 링크
```
cd $HOME/python/Python-3.12.6

./configure \
  --prefix=$HOME/python/3.12 \
  --enable-optimizations \
  --with-ensurepip=install

make -j$(nproc)
make altinstall

# 실행파일 링크

cd $HOME/python/3.12/bin
ls
2to3-3.12  idle3.12  pip3.12  pydoc3.12  python3.12  python3.12-config
ln -s python3.12 python3
ln -s python3.12 python
ln -s pip3.12 pip3
ln -s pip3.12 pip

# 실행 확인

./python --version
3.12.6 ...

./pip --version
24.x ...

```
 파이썬 실행 환경 설정
```
vi .bash_profile 

export PYTHON_HOME=$HOME/python/3.12
export LD_LIBRARY_PATH=$PYTHON_HOME/lib:$LD_LIBRARY_PATH
export PATH=$PYTHON_HOME/bin:$PATH

source .bash_profile
```

현재 Python이 사용하는 site-packages 경로 확인
```
python -c "import site; print(site.getsitepackages())"
```

### 4. PIP 업그레이드

온라인 서버에서 패키징한 라이브러리를 오프라인 서버로 이동했으면 오프라인 서버에서 다음과 같이 진행합니다. 

```
su - 계정명    # python 사용 계정으로

pip --version
pip 24.0

python -m pip install --upgrade /opt/python/pip_offline/pip-25.3-py3-none-any.whl

pip --version
pip 25.3 
```

### 5. 오라클 벡터검색 기본 라이브러리 설치

온라인 서버에서 패키징한 벡터검색 기본 라이브러리를 오프라인 서버로 이동했으면 오프라인 서버에서 다음과 같이 진행합니다.
```
su - 계정명

cp /tmp/def_whl.tar /opt/python/.
cd /opt/python
tar xvf def_whl.tar
ls

cd /opt/python/def_whl
python3 -m pip install --no-index --find-links=/opt/python/def_whl -r /opt/python/def_whl/def_whl.txt
```

### 6. oml4py 설치

이 파일은 공통자원으로 사용이 가능하기 떄문에 공통자원 디렉토리에 저장해 놓고 필요한 사용자 별로 자신의 패키지 셋에 설치하여 사용합니다. 온라인에서 다운로드 된 파일을 오프라인 서버로 이동했으면 다음과 같이 진행합니다.

```
su - oracle

cd /opt/oracle/oml4py

cp /tmp/V1048628-01.zip /opt/oracle/oml4py/.

cd /opt/oracle/oml4py
unzip V1048628-01.zip

pip3 install /opt/oracle/oml4py/client/oml-2.1-cp312-cp312-linux_x86_64.whl

# oml 확인

python3
import oml
from oml.utils import ONNXPipelineConfig
ONNXPipelineConfig.show_preconfigured()

모델 리스트가 나오면 성공!
```

### 7. jupyterlab 설치 

* jupyter lab은 파이썬 GUI 유틸리티입니다. 필요하신 분만 설치해서 사용하십시오.
* 기존 서비스 URL은 http://x.x.x.x:7100/lab이며 7100 입니다.계정별로 서비스 포트를 분리하여 사용하세요. 

7.1 jupyter lab 설치 
```
su - 계정명       -- python 사용 계정 

cp /tmp/jupyterlab_wheelhouse.tar /opt/python
cd /opt/python
tar xvf jupyterlab_wheelhouse.tar
ls

python -m pip install --no-index --find-links=/opt/python/jupyterlab_wheelhouse jupyterlab

python -m pip show -f jupyterlab

python -c "import sqlite3; print(sqlite3.sqlite_version)"
```
버전 확인 (이게 통과되야 끝)

7.2 jupyterlab 개별 환경 설정

각 계정마다 jupyterlab 환경을 사용할 경우 다으을 참고하여 포트 및 실행 위치를 분리하여 사용할 수 있습니다.

jupyterlab 패스워드 준비

```
su - 계정명     --python 사용 계정

ipython
from jupyter_server.auth import passwd
passwd()
Enter password:
Verify password:
Out[3]: 'argon2:$argon2id$v=19$m=10240,t=10,p=8$BDOVgQ5ZF/qfMrQvj/I0SQ$xZHS9lOLwDvZ+/2m/v3DqxSAHU6DQn2eYy2DAgQjrFk'
```
- 입력한 패스워드 기억해 둡니다(브라우저 로그인 화면에서 패스워드 입력 필요함)
- Out[3] 출력값은 jupyter config 파일에 복붙해서 사용합니다. 복사해두세요.

jupyterlab config 파일 생성 및 업데이트

```
jupyter lab --generate-config
cd ~/.jupyter/jupyter_lab_config.py

vi jupyter_lab_config.py 
#---------- vi
c.LabServerApp.config_file_name = 'jupyter_lab_config.py'

#외부접속 허용
c.ServerApp.allow_origin = '*'

#작업경로 설정
# 계정홈의 하위 디렉토리로 설정
c.ServerApp.notebook_dir = '/home/devadmin/labs/'

#아이피 설정 -  외부 접속 허용(listen)
c.ServerApp.ip = '0.0.0.0'

#포트 설정
# 원하는 포트 번호 입력(7100 ~ )
c.ServerApp.port = 7100

# 비밀번호 암호키 설정 for after 2.x
# 앞에서 만든 패스워드 암호화 값 사용
c.PasswordIdentityProvider.hashed_password = 'argon2:$argon2id$v=19$m=10240,t=10,p=8$op66nd7xHgWEtWM+PDL72w$JWxK2/yab2jrw7qA9J8+QzrMWihf3dZSDy7UYAJGsHU'
c.ServerApp.token = ''
#------------ end vi
```
jupyter lab 실행

```
mkdir ~/labs

nohup jupyter lab --config $HOME/.jupyter/jupyter_lab_config.py &
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

파이어월에서 7100 또는 사용자 지정 서비스 포트 개방 

### 8. ONNX 임베딩 모델 로딩

* 오라클이 제공하는 임베딩 모델 32종은 인터넷 환경에서 다운로드 후 DB에 로딩하는 방법을 사용합니다. 인터넷 연결이 안되는 오프라인 환경에서는 우선 인터넷 환경에서 오라클 ONNX 유티리티(python 유틸리티)를 사용하여 모델을 다운로드하고, 다운로드된 ONNX 모델 파일을 오프라인 DB 서버로 옮긴 후 ONNX 유틸리티로 DB에 로딩을 할수 있습니다.
* 온라인 DB서버에서 다운로드 된 ONNX 모델을 오프라인 서버의 /u01/models 이동했으면 다음과 같이 진행합니다.

8.1 오라클 임베딩 모델 환경

* 모델 저장 디렉토리 : /u01/models  -- 디렉토리명 확인하세요
* 임베딩 모델은 오라클 내에서 공통모델자원으로 사용이 가능합니다. 같은 모델을 스키마마다 저장, 사용할 경우 테이블 스페이스(스토리지) 절약, 임베딩/쿼리에 혼선 방지 등 통합모델 관리 차원에서 모델관리용 스키마를 별도로 만들어 통합관리하는 방법을 권고 드립니다.

- 모델 관리 스키마 생성
```sql
su - oracle

sqlplus / as sysdba

alter system set container=pdb1;
show con_nme;
pdb1          -- 확인

create user modeladm identified by 패스워드 
default tablespace 테이블스페이스명 
quota unlimited on 테이블페이스명;

grant connect, resource to modeladm;
grant create any directory to modeladm;
```

임베딩 모델의 DB 로딩 및 모델 조회;
```sql
su - oracle

sqlplus modeladm/패스워드@xdwa

CREATE OR REPLACE DIRECTORY VEC_DUMP as '/u01/models';  -- 디렉토리 위치 확인

EXECUTE DBMS_VECTOR.LOAD_ONNX_MODEL('VEC_DUMP','xxx.onnx','xxx');

PL/SQL procedure successfully completed.

# xxx.onnx는 ONNX 임베딩 모델의 파일명, xxx는 DB에서 사용할 모델명입니다. DB에서는 -(마이너스)는 예약어로써 모델명에 - 를 넣으면 에러를 냅니다. 언더바나 다른 문자를 사용하세요.

SELECT MODEL_NAME, MINING_FUNCTION, ALGORITHM,
ALGORITHM_TYPE, MODEL_SIZE
FROM user_mining_models
ORDER BY MODEL_NAME;
```

임베딩 모델 공유

```sql
sqlplus modeladm/패스워드@xdwa

SELECT MODEL_NAME, MINING_FUNCTION, ALGORITHM,
ALGORITHM_TYPE, MODEL_SIZE
FROM user_mining_models
ORDER BY MODEL_NAME;

garnt execute on 모델명 to 스키마;
```

임베딩 모델 사용

```sql
sqlplus 스키마/패스워드@xdwa

create synonym 모델명 for modeladm.모델명;

SELECT TO_VECTOR(VECTOR_EMBEDDING(모델명 USING '문장' as data)) AS embedding;
```

오라클23ai에서 제공되는 다양한 벡터관련 함수 유틸리티와 결합하여 인디비 임베딩을 처리할 수 있습니다.

샘플 벡터 쿼리

백터검색 및 RAG 샘플
https://github.com/kairkowy/handon-labs-for-vector-search/tree/main/similarity_search 를 참고하세요

ONNX 다운로드 및 실행 샘플
https://github.com/kairkowy/handon-labs-for-vector-search/tree/main/ONNX 를 참고하세요

임베딩 모델의 관리

DB에 로딩된 임베딩 모델의 관리, 삭제 등의 방법은 오라클 AI 벡터검색 사용자 가이드 https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/get-started-node.html 을 참고하세요. 

### 9. RAG for Oracle

9.1 ollama 서비스 환경

- 서비스 포트 : 11434
- 서비스 관리 계정 : ollama

9.2 ollama 서비스 관리

```
su - ollama

systemctl --user status ollama    -- 서비스 상태 확인
systemctl --user start ollama     -- 서비스 시작
systemctl --user stop ollam       -- 서비스 중지
systemctl --user enable ollama    -- 부팅시 자동 실행
systemctl --user daemon-reload    --서비스 리로드

```
9.3 ollama 서비스 모델 확인

```
su - ollama
ollama list
```
* ollama 서비스 모델 오프라인 이동 방법은 https://github.com/kairkowy/handon-labs-for-vector-search/blob/main/similarity_search/OLLAMA%20%EC%98%A4%ED%94%84%EB%9D%BC%EC%9D%B8%20%EC%84%A4%EC%B9%98%20%EB%B0%8F%20RPM%20%EC%84%A4%EC%B9%98%20%EB%B0%A9%EB%B2%95.md 을 참고하세요

9.4 ollama LLM 질문/임베딩 서비스 확인

- ollama 서버에서(질문)
```
curl -X POST http://localhost:11434/api/generate -d '{"model" :"llama3.2","prompt": "IT기업 오라클사를 소개해주세요","stream" : false}'
```

- oraclient 서버에서(임베딩)
```
curl -X POST http://ollama:11434/api/embeddings -d '{"model" : "llama3.2","prompt": "IT기업 오라클사를 소개해주세요", "stream" : false}'
```

9.5 ollama-오라클DB RAG

DB 스키마에 APIs 권한 부여 

```
su - oracle      
sqlplus / as sysdba

alter session set container=db1;
show con_name;

GRANT DB_DEVELOPER_ROLE, create credential to 스키마;
GRANT execute on SYS.UTL_HTTP to 스키마
GRANT execute on sys.dbms_network_acl_admin to 스키마;
```
ollama API용 ACL 생성

```
sqlplus 스키마/패스워드@xdwa

show user;
스키마 확인

# ACL 생성

BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => '*',
    ace => xs$ace_type(privilege_list => xs$name_list('connect'),
                       principal_name => '스키마',
                       principal_type => xs_acl.ptype_db));
END;
/
```

오라클 API 이용한 임베딩 테스트

  sqlplus 스키마/패스워드@xdwa

```

var embed_ollama_params clob;
exec :embed_ollama_params := '{"provider": "ollama","host":"local","url": "http://x.x.x.142:11434/api/embeddings","model":"llama3.2"}';

select dbms_vector.utl_to_embedding('문장', json(:embed_ollama_params)) ollama_output;  -- 임베딩 쿼리

OLLAMA_OUTPUT
--------------------------------------------------------------------------------
[-2.1026895E+000,1.87008286E+000,-8.44160765E-002,-1.41829121E+000,


var gent_ollama_params clob;
exec :gent_ollama_params := '{"provider": "ollama","host":"local","url": "http://x.x.x.142:11434/api/generate","model":"llama3.2"}';

select dbms_vector.utl_to_generate_text('군인공제회 소개해주세요', json(:gent_ollama_params)) ollama_output;  -- 질문 쿼리

OLLAMA_OUTPUT
--------------------------------------------------------------------------------
....
```
* 실무 적용 샘플 RAG는 https://github.com/kairkowy/handon-labs-for-vector-search/tree/main/similarity_search 의 2-1.RAG_DOC.ipynb, 2-2.RAG_Table.ipynb 파일을 참조하세요.

---------
end of document

감사합니다.



