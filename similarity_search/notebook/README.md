# Oracle Linux 9에서 similarity_search Notebook 환경 구성

Oracle Linux 9 서버에 `lab` 계정으로 접속하여 이 저장소의 `.ipynb` 실습을 실행하는 순서입니다. JupyterLab 화면에서 Jupyter Notebook 파일을 열어 실행합니다. 명령어마다 실행 위치를 구분했으며, 서버에 실제 접속하거나 설치를 수행한 기록은 아닙니다.

## 환경과 실행 순서

| 항목 | 이 문서의 기준 |
| --- | --- |
| 서버 | Oracle Linux 9.4 이상, 공인 IP `129.80.xxx.xxx` |
| SSH 접속 계정 | `lab` — `/home/lab` 홈 디렉터리가 있는 기존 OS 계정 |
| Python | `lab` 계정으로 Python 3.12.16 소스 설치, 전용 가상환경 `/home/lab/venvs/vector-lab` |
| 실습 폴더 | `/home/lab/labs/Oracle26ai_AI_Feature/similarity_search` |
| Jupyter | 서버의 `127.0.0.1:8888`에서 실행하고 SSH 터널로 접속 |
| DB | 별도로 준비한 Oracle AI Database PDB, 실습 스키마·모델·권한 |
| LLM | RAG를 진행하는 경우에만 Ollama와 `llama3.2` 등 생성 모델 |

문서의 `<SERVER_IP>`는 전달받은 실제 공인 IP로 바꿉니다. 가려진 `129.80.xxx.xxx`를 접속 명령에 그대로 사용하지 않습니다. **OS 계정 `lab`과 DB 계정은 별개**입니다. 아래 DB 계정 예시 `LABADMIN`은 실제 준비한 DB 계정으로 변경합니다.

진행 순서는 **SSH 접속 → OS 패키지 → 저장소 → 가상환경 → 패키지·커널 → 접속 변수 → Jupyter 설정 → SSH 터널 → Notebook 점검 → 실습**입니다.

## 1. PC에서 서버 접속

**실행 위치: 사용자 PC의 PowerShell**

```powershell
$LabHost = '<SERVER_IP>'
ssh "lab@$LabHost"
```

SSH 키 인증을 사용하는 서버는 발급받은 개인 키의 실제 경로를 지정합니다.

```powershell
$LabHost = '<SERVER_IP>'
ssh -i "$env:USERPROFILE\.ssh\lab_key" "lab@$LabHost"
```

첫 접속 시 서버 호스트 키의 지문을 관리자에게 받은 값과 확인합니다. 접속이 안 되면 SSH 키·서버 계정과 서버의 TCP 22 접근 경로를 확인합니다. OCI 서버라면 보안 목록 또는 NSG에서 사용자 PC의 접근도 허용되어 있어야 합니다.

**실행 위치: 서버 SSH 터미널, `lab` 계정**

```bash
whoami
printf '%s\n' "$HOME"
cat /etc/oracle-release
uname -m
```

계정은 `lab`, 홈은 `/home/lab`인지 확인합니다. 다른 계정으로 접속했다면 이후 작업 전에 `lab`으로 로그인합니다.

## 2. OS 패키지 설치

Python은 `lab` 계정으로 소스를 다운로드·빌드하여 `/home/lab/python/3.12.16`에 설치합니다. OS 기본 Python은 그대로 사용하며, Python 설치 과정에서는 `sudo`를 사용하지 않습니다.

### 2-1. 빌드에 필요한 OS 패키지 준비

**실행 위치: 서버 SSH 터미널, sudo가 가능한 계정 — 관리자 준비 작업**

컴파일러와 개발 라이브러리만 OS 패키지로 설치합니다. `lab`에 sudo 권한이 없으면 이 단계만 관리자에게 요청한 뒤, 다음 단계부터 `lab`으로 진행합니다.

```bash
sudo dnf repolist
sudo dnf install -y git curl tmux tar xz gcc make pkgconf-pkg-config \
  openssl-devel bzip2-devel libffi-devel zlib-devel xz-devel \
  readline-devel sqlite-devel ncurses-devel libuuid-devel tk-devel
```

### 2-2. lab 계정으로 Python 소스 다운로드

**실행 위치: 서버 SSH 터미널, `lab` 계정**

```bash
whoami
mkdir -p /home/lab/src /home/lab/python
cd /home/lab/src
PYTHON_VERSION=3.12.16
curl --fail --location --show-error \
  --output "Python-${PYTHON_VERSION}.tar.xz" \
  "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz"
tar -xf "Python-${PYTHON_VERSION}.tar.xz"
cd "/home/lab/src/Python-${PYTHON_VERSION}"
```

`whoami` 결과가 `lab`인지 확인합니다. 예제 버전은 [Python 3.12.16 공식 배포본](https://www.python.org/downloads/release/python-31216/)입니다. 버전을 변경하면 아래 설치 경로와 4단계의 가상환경 생성 명령도 같은 버전으로 맞춥니다.

### 2-3. lab 홈 디렉터리에 빌드·설치

**실행 위치: 서버 SSH 터미널, `lab` 계정 — 위 Python 소스 디렉터리**

```bash
./configure --prefix="/home/lab/python/${PYTHON_VERSION}" \
  --with-ensurepip=upgrade
make -j2
make altinstall
/home/lab/python/3.12.16/bin/python3.12 --version
/home/lab/python/3.12.16/bin/python3.12 -m pip --version
/home/lab/python/3.12.16/bin/python3.12 -c \
  "import ssl, sqlite3, bz2, lzma, ctypes, zlib, readline; print(ssl.OPENSSL_VERSION)"
```

각 명령의 성공을 확인한 후 다음 명령으로 진행합니다. 컴파일 중 SSH 세션을 다시 열었다면 `PYTHON_VERSION=3.12.16`을 다시 지정하고 해당 소스 디렉터리로 이동합니다. 병렬 빌드는 `-j2`를 기준으로 하며 메모리가 부족하면 `make -j1`로 진행합니다.

`make altinstall`은 버전이 붙은 실행 파일을 설치합니다. `sudo make install`이나 `/usr/bin/python3` 교체는 수행하지 않습니다. 이후에는 설치된 실행 파일의 절대 경로로 가상환경을 생성하므로 전역 PATH 변경도 필요하지 않습니다. [Python Unix 소스 빌드](https://docs.python.org/3.12/using/unix.html) · [설치 경로 지정](https://docs.python.org/3.12/using/configure.html#cmdoption-prefix)

나머지 가상환경·Jupyter 설정도 `lab`으로 수행합니다. 이 구성에서는 Jupyter용 공인 TCP 8888 포트를 추가로 열 필요가 없습니다.

## 3. 실습 저장소 받기

**실행 위치: 서버 SSH 터미널, `lab` 계정**

```bash
mkdir -p /home/lab/labs /home/lab/venvs
cd /home/lab/labs
git clone https://github.com/kairkowy/Oracle26ai_AI_Feature.git
cd /home/lab/labs/Oracle26ai_AI_Feature/similarity_search
ls -1 *.ipynb
ls -l user_functions.py notebook/requirements.txt
```

이미 같은 경로에 저장소가 있으면 다시 clone하지 않고, 작업 내용을 먼저 확인한 뒤 갱신합니다.

```bash
cd /home/lab/labs/Oracle26ai_AI_Feature
git status --short
git pull --ff-only
cd similarity_search
```

수정된 파일이나 충돌이 있으면 보존·정리한 후 갱신합니다. 노트북 6개와 `user_functions.py`, `data` 폴더가 보여야 합니다. 설치 중 인터넷으로 Oracle Linux 저장소, python.org, GitHub, PyPI 및 패키지 배포 호스트에 접근할 수 있어야 합니다. 폐쇄망은 Python 소스 아카이브와 OS 빌드 의존 패키지를 먼저 준비하고, 같은 OS·CPU 아키텍처·Python 버전의 온라인 환경에서 Python 의존 wheel도 준비해 반입합니다.

## 4. Python 가상환경 생성과 패키지 설치

**실행 위치: 서버 SSH 터미널, `lab` 계정**

```bash
/home/lab/python/3.12.16/bin/python3.12 -m venv /home/lab/venvs/vector-lab
source /home/lab/venvs/vector-lab/bin/activate
python --version
command -v python
python -m pip install --upgrade pip
cd /home/lab/labs/Oracle26ai_AI_Feature/similarity_search
python -m pip install -r notebook/requirements.txt
python -m pip check
```

`command -v python` 결과는 `/home/lab/venvs/vector-lab/bin/python`이어야 합니다. `sudo pip`로 설치하지 않습니다. 가상환경을 다시 만들 때는 기존 경로의 사용 여부를 먼저 확인합니다.

| 패키지 | 용도 |
| --- | --- |
| `jupyterlab`, `ipykernel` | Notebook UI와 Python 커널 |
| `oracledb`, `pandas` | DB 접속, 조회 결과 표 처리 |
| `pillow`, `matplotlib` | 이미지 검색 입력과 결과 표시 |
| `langchain-core`, `langchain-ollama` | 문서·테이블 RAG의 Ollama 호출 |

이 저장소의 실행용 Notebook은 `user_functions.py`를 사용합니다. 기본 실행에 `import_ipynb`, OML4Py, PyTorch, Transformers, ONNX 변환 패키지를 설치할 필요는 없습니다. ONNX 모델의 변환·로딩을 별도 Python 코드로 수행하는 경우에만 해당 도구의 환경을 추가로 준비합니다.

`python-oracledb`는 기본 Thin 모드로 DB에 접속하므로 이 경로에는 Oracle Instant Client가 필수가 아닙니다. 모델은 DB에 미리 적재되어 있어야 합니다. [python-oracledb 설치와 Thin 모드](https://python-oracledb.readthedocs.io/en/latest/user_guide/installation.html)

[requirements.txt](requirements.txt)는 설치 입력 목록이며 서버에서 실증한 고정 버전 lock 파일은 아닙니다. 설치 후 실제 버전을 로컬 파일로 기록합니다.

```bash
mkdir -p /home/lab/.config/vector-lab
chmod 700 /home/lab/.config/vector-lab
python -m pip freeze > /home/lab/.config/vector-lab/requirements-installed.txt
```

## 5. Notebook용 커널 등록

**실행 위치: 서버 SSH 터미널, 가상환경 활성화 상태**

```bash
python -m ipykernel install --user \
  --name vector-lab \
  --display-name "Python (vector-lab)"
jupyter kernelspec list
```

목록에 `vector-lab`이 보여야 합니다. 나중에 Notebook을 열면 **Kernel → Change Kernel → Python (vector-lab)**을 선택합니다. 같은 이름으로 재등록하면 해당 커널 설정이 갱신됩니다. [IPython 커널 등록](https://ipython.readthedocs.io/en/stable/install/kernel_install.html)

## 6. DB·Ollama 접속 변수 준비

**실행 위치: 서버 SSH 터미널, `lab` 계정**

아래 파일은 처음 한 번 작성합니다. 기존 파일이 있으면 내용을 먼저 확인하고 필요한 값만 수정합니다. `DB_HOST`, 포트와 `FREEPDB1` 서비스는 DBA가 제공한 실제 값으로 바꿉니다. Notebook 서버 공인 IP가 DB 호스트와 같다고 가정하지 않습니다.

```bash
cat > /home/lab/.config/vector-lab/env.sh <<'EOF'
export ORACLE_USER='LABADMIN'
export ORACLE_DSN='DB_HOST:1521/FREEPDB1'
export OLLAMA_BASE_URL='http://127.0.0.1:11434'
export OLLAMA_GENERATE_URL='http://127.0.0.1:11434/api/generate'
export OLLAMA_MODEL='llama3.2'
EOF
chmod 600 /home/lab/.config/vector-lab/env.sh
vi /home/lab/.config/vector-lab/env.sh
source /home/lab/.config/vector-lab/env.sh
```

DB 비밀번호는 파일에 저장하지 않고 Notebook의 `getpass` 입력창에 입력합니다. `ORACLE_PASSWORD` 환경 변수를 지정하지 않으면 기존 노트북이 비밀번호를 물어봅니다.

Ollama의 `127.0.0.1` 예시는 Jupyter 서버와 DB 서버가 모두 같은 호스트의 Ollama에 접근하는 경우입니다. 서버가 다르면 다음 두 값을 호출 주체별로 설정합니다.

| 환경 변수 | 접속하는 주체 | 올바른 주소 |
| --- | --- | --- |
| `OLLAMA_BASE_URL` | Notebook Python 프로세스 | Notebook 서버에서 접근 가능한 Ollama 기본 URL |
| `OLLAMA_GENERATE_URL` | DB 서버의 REST 호출 | DB 서버에서 접근 가능한 Ollama `/api/generate` URL |

기존 예제의 `service-ollama` 호스트명이 실제 DNS에서 해석되지 않으면 위 환경 변수로 변경합니다. 환경 변수는 **Jupyter를 실행하기 전에** 읽어야 새로 생성하는 커널이 상속합니다. 설정을 바꾼 뒤에는 Jupyter 서버와 커널을 재시작합니다.

## 7. Jupyter 비밀번호와 작업 경로 설정

**실행 위치: 서버 SSH 터미널, 가상환경 활성화 상태**

```bash
mkdir -p /home/lab/.jupyter
chmod 700 /home/lab/.jupyter
jupyter server password
```

브라우저 로그인에 사용할 비밀번호를 두 번 입력합니다. OS 로그인 비밀번호·DB 비밀번호와는 별도입니다. 생성되는 해시나 로그인 토큰은 저장소에 올리지 않습니다. [Jupyter 비밀번호 설정](https://jupyter-server.readthedocs.io/en/latest/operators/public-server.html)

설정 파일이 이미 있으면 먼저 백업한 뒤 다음 내용을 반영합니다.

```bash
if [ -f /home/lab/.jupyter/jupyter_server_config.py ]; then
  cp -p /home/lab/.jupyter/jupyter_server_config.py \
    "/home/lab/.jupyter/jupyter_server_config.py.bak.$(date +%Y%m%d%H%M%S)"
fi
cat > /home/lab/.jupyter/jupyter_server_config.py <<'EOF'
c = get_config()
c.ServerApp.ip = '127.0.0.1'
c.ServerApp.port = 8888
c.ServerApp.port_retries = 0
c.ServerApp.open_browser = False
c.ServerApp.root_dir = '/home/lab/labs/Oracle26ai_AI_Feature/similarity_search'
EOF
chmod 600 /home/lab/.jupyter/jupyter_server_config.py
```

Jupyter는 loopback 주소에서만 대기합니다. SSH 터널이 브라우저와 서버를 연결합니다. 토큰·비밀번호 인증을 끄거나 `allow_origin='*'`를 추가할 필요가 없습니다. 기존 설정에 별도 확장·프록시 구성이 있으면 백업 파일과 비교해 필요한 설정을 합칩니다.

## 8. JupyterLab 실행

**실행 위치: 서버 SSH 터미널, `lab` 계정**

SSH 연결이 끊겨도 서버 실행을 유지하려면 tmux 세션에서 실행합니다.

```bash
tmux new -s vector-notebook
source /home/lab/venvs/vector-lab/bin/activate
source /home/lab/.config/vector-lab/env.sh
cd /home/lab/labs/Oracle26ai_AI_Feature/similarity_search
jupyter lab --no-browser
```

로그에 `http://127.0.0.1:8888/lab` 형태의 주소가 보여야 합니다. `Ctrl+B`를 누른 뒤 `D`를 누르면 서버를 유지한 채 tmux에서 나옵니다. 이미 세션이 있다면 `tmux attach -t vector-notebook`으로 돌아갑니다. tmux는 SSH 연결 종료에는 대응하지만 OS 재부팅 시 자동 기동되지는 않습니다.

같은 서버의 별도 SSH 터미널에서 대기 주소를 확인할 수 있습니다.

```bash
ss -lnt | grep ':8888'
curl -I http://127.0.0.1:8888/lab
```

대기 주소는 `127.0.0.1:8888`이어야 합니다. 로그인 전 HTTP 리다이렉트가 반환될 수 있으며, HTTP 응답 수신은 서버 기동만 확인합니다. 최종 로그인과 커널 실행은 다음 단계에서 확인합니다.

## 9. PC에서 SSH 터널과 브라우저 접속

**실행 위치: 사용자 PC의 새 PowerShell 창**

```powershell
$LabHost = '<SERVER_IP>'
ssh -N -L 8888:127.0.0.1:8888 -o ExitOnForwardFailure=yes "lab@$LabHost"
```

SSH 키를 사용하는 경우 다음 명령을 사용합니다.

```powershell
$LabHost = '<SERVER_IP>'
ssh -i "$env:USERPROFILE\.ssh\lab_key" -N -L 8888:127.0.0.1:8888 -o ExitOnForwardFailure=yes "lab@$LabHost"
```

터널 창은 출력 없이 대기하는 것이 정상입니다. 창을 유지한 상태로 PC 브라우저에서 [JupyterLab 접속](http://127.0.0.1:8888/lab)을 열고 7단계 비밀번호로 로그인합니다. 공인 IP의 `:8888` 주소로 접속하지 않습니다.

PC의 8888 포트를 다른 프로그램이 사용 중이면 로컬 포트만 8889로 바꿉니다.

```powershell
ssh -N -L 8889:127.0.0.1:8888 -o ExitOnForwardFailure=yes "lab@$LabHost"
```

이 경우 브라우저 주소는 `http://127.0.0.1:8889/lab`입니다. 키 인증이면 위와 같이 `-i` 옵션도 함께 넣습니다.

## 10. Notebook에서 Python 환경과 DB 접속 확인

**실행 위치: JupyterLab의 새 Python Notebook, 커널 `Python (vector-lab)`**

새 Notebook은 파일 탐색기의 최상위 `similarity_search` 폴더에서 만듭니다. `notebook` 하위 폴더에서 만들었다면 먼저 `%cd /home/lab/labs/Oracle26ai_AI_Feature/similarity_search`를 실행합니다.

첫 셀에서 실행 파일·작업 경로·import를 확인합니다.

```python
import sys
from pathlib import Path
import oracledb
import pandas as pd
from PIL import Image
import matplotlib.pyplot as plt
from langchain_core.prompts import ChatPromptTemplate
from langchain_ollama.llms import OllamaLLM
from user_functions import get_conn_cursor, get_db_version

print(sys.executable)
print(Path.cwd())
print("Thin mode:", oracledb.is_thin_mode())
assert Path("user_functions.py").is_file()
assert Path("data/images/val_data").is_dir()
```

`sys.executable`이 `/home/lab/venvs/vector-lab/bin/python`인지 확인합니다. 다른 Python이면 커널을 변경하고 다시 시작합니다.

다음 셀은 DB 접속·현재 PDB·모델 목록만 조회하며 테이블을 변경하지 않습니다.

```python
import os
from getpass import getpass

db_user = os.environ["ORACLE_USER"]
db_dsn = os.environ["ORACLE_DSN"]
db_password = getpass("DB 비밀번호: ")
with oracledb.connect(user=db_user, password=db_password, dsn=db_dsn) as conn:
    with conn.cursor() as cursor:
        cursor.execute("SELECT USER, SYS_CONTEXT('USERENV','CON_NAME') FROM dual")
        print("사용자 / PDB:", cursor.fetchone())
        cursor.execute("SELECT model_name FROM user_mining_models ORDER BY model_name")
        print("ONNX 모델:", [row[0] for row in cursor])
del db_password
```

모델 목록에서 문서·테이블용 `MULTILINGUAL_E5_SMALL`, 이미지용 `CLIP_VIT_LARGE_PATCH14_IMG`·`CLIP_VIT_LARGE_PATCH14_TXT`를 확인합니다. 선택한 실습에 필요한 모델이 없으면 DBA·모델 담당자가 먼저 적재합니다. Python 패키지 설치만으로 DB에 모델이 생성되지는 않습니다.

## 11. DB 데이터와 Ollama 준비

Notebook 설치와 DB 데이터 준비는 별도입니다. [공통 준비](../00.Setup.md)에 따라 권한·DIRECTORY·테이블을 준비하고 각 실습 문서의 SQL을 실행합니다. **Notebook의 Python 셀에 SQL 본문을 그대로 붙이지 않고**, SQL*Plus·SQLcl 등 SQL 클라이언트에서 실행합니다.

| 실습 | 필요한 테이블과 자료 |
| --- | --- |
| 문서 검색 | `DOC_STORE`, `DOC_STORE_CHUNKS`, [문서 데이터 준비 SQL](../1-1.simsearch_doc.md#테이블-생성과-샘플-데이터-적재-sql) |
| 이미지 검색 | `IMG_TBL`, [이미지 데이터 준비 SQL](../1-2.smsearch_image.md#테이블-생성과-샘플-데이터-적재-sql) |
| 문서 RAG | `RAG_TBL`, `RAG_TBL_V`, [PDF 데이터 준비 SQL](../2-1.RAG_DOC.md#테이블-생성과-샘플-데이터-적재-sql) |
| 테이블 RAG | `BROAD_TBL`, [보도자료 데이터 준비 SQL](../2-2.RAG_Table.md#테이블-생성과-샘플-데이터-적재-sql) |
| Hybrid | 위 문서 데이터와 별도 [Hybrid 인덱스](../3.Hybrid_search.md#하이브리드-인덱스-준비) |

`BFILENAME`에 사용되는 DIRECTORY는 **DB 서버**의 파일 경로입니다. Notebook 서버의 `/home/lab/labs/.../data`와 자동으로 연결되지 않습니다. DB가 다른 서버에 있으면 파일도 DB 서버로 복사해야 합니다. 같은 서버라도 DB Oracle OS 계정이 `/home/lab` 아래 파일을 읽을 수 있다고 가정하지 말고, [공통 준비](../00.Setup.md)의 전용 DB 데이터 경로와 읽기 권한을 사용합니다.

RAG를 선택했다면 먼저 준비된 Ollama 서비스의 모델 목록을 확인합니다.

**실행 위치: 서버 SSH 터미널, 접속 변수 파일을 읽은 상태**

```bash
curl --fail --show-error --connect-timeout 5 "$OLLAMA_BASE_URL/api/tags"
```

선택한 `OLLAMA_MODEL`이 목록에 있어야 합니다. Ollama 서비스 설치·모델 다운로드가 필요하면 Ollama 서버 담당자가 준비합니다. [기존 환경 참고 자료](../오라클%20-%20Ollama%20환경%20RAG%20예제%20시나리오%20준비.md)는 과거 구성 기록이므로 이 가이드의 `lab` 경로와 실제 서비스 주소에 맞춰 확인합니다.

문서 RAG의 DB REST 경로는 **DB 서버 → Ollama** 네트워크 연결과 DB ACL도 필요합니다. Notebook 터미널의 curl 성공만으로 DB 호출 성공이 보장되지는 않습니다. 이 준비가 끝나기 전에도 문서·이미지 유사도 검색은 LLM 없이 진행할 수 있습니다.

## 12. 실습 Notebook 실행과 종료

JupyterLab의 파일 탐색기에서 최상위 폴더로 돌아가 다음 순서로 엽니다. 처음에는 셀을 하나씩 실행해 오류가 발생하는 단계를 확인합니다.

1. [1-1.simsearch_doc.ipynb](../1-1.simsearch_doc.ipynb): 문서 조회 → 청킹·임베딩 → 벡터 검색.
2. [1-2.smsearch_image.ipynb](../1-2.smsearch_image.ipynb): 이미지 임베딩 → 이미지·텍스트 검색.
3. [2-1.RAG_DOC.ipynb](../2-1.RAG_DOC.ipynb): 문서 검색 근거를 추가한 LLM 응답 비교.
4. [2-2.RAG_Table.ipynb](../2-2.RAG_Table.ipynb): 보도자료 행 검색과 RAG.
5. [3.Hybrid_search.ipynb](../3.Hybrid_search.ipynb): 키워드·의미 검색 결합.

[user_functions.ipynb](../user_functions.ipynb)는 함수 참고용입니다. 실습은 같은 폴더의 `user_functions.py`를 import하므로 먼저 실행할 필요가 없습니다. 노트북 안의 테이블 생성 SQL은 11단계에서 따로 실행하며, 벡터 초기화·TRUNCATE·인덱스 삭제 셀은 해당 실습 객체를 대상으로 하는지 확인합니다.

실습이 끝나면 커널을 종료합니다. Jupyter 서버까지 종료할 때는 서버 터미널에서 `tmux attach -t vector-notebook`으로 돌아가 `Ctrl+C` 후 종료 확인에 응답합니다. PC의 SSH 터널도 `Ctrl+C`로 종료합니다.

다음 접속 때는 새로 설치하지 않고 `lab`으로 SSH 로그인한 후 8~9단계를 수행합니다. 기존 tmux 세션이 실행 중이면 attach만 하면 됩니다.

## 문제별 확인 사항

| 증상 | 확인·조치 |
| --- | --- |
| 빌드 의존 패키지를 찾지 못함 | 2-1단계의 패키지 이름, OS 저장소와 네트워크를 관리자와 확인 |
| `configure: error` 또는 `make` 실패 | 2-1단계의 개발 패키지와 빌드 로그 확인, 메모리 부족 시 `make -j1` 사용 |
| `_ssl`·`_ctypes` 등 모듈을 찾지 못함 | 해당 개발 라이브러리를 준비한 뒤 Python configure·빌드·설치를 다시 수행하고 2-3단계 import 점검 |
| `python3.12: command not found` | 전역 명령 대신 `/home/lab/python/3.12.16/bin/python3.12` 절대 경로 사용 |
| `ModuleNotFoundError` | `sys.executable`과 선택한 커널 확인, 해당 venv에서 requirements 재설치 |
| `No module named user_functions` | 작업 디렉터리를 `similarity_search`로 변경하고 `user_functions.py` 존재 확인 |
| 이미지 파일을 찾지 못함 | `Path.cwd()`와 `data/images/val_data` 상대 경로 확인 |
| 브라우저 접속 실패 | tmux의 서버 로그, 서버 `127.0.0.1:8888` 대기, PC SSH 터널 순서로 확인 |
| `Address already in use` | PC 측 포트 충돌이면 로컬 8889 사용, 서버 측이면 기존 Jupyter 프로세스 확인 |
| `ORACLE_USER` KeyError | Jupyter 실행 전 env.sh를 source했는지 확인 후 서버·커널 재시작 |
| DB 연결·인증 오류 | `ORACLE_DSN`의 호스트·서비스·포트와 DB 사용자·비밀번호·네트워크 확인 |
| ONNX 모델 또는 테이블 없음 | 올바른 PDB·스키마인지 확인 후 해당 실습의 DB 준비 진행 |
| Ollama 연결 실패 | Python용 기본 URL과 DB용 `/api/generate` URL의 호출 위치·모델·DB ACL 구분 |

작성 기준일: 2026-11-26. 공식 설치 문서와 저장소 import·경로를 대조했으며, 대상 서버에서의 설치·접속·Notebook 실행은 검증하지 않았습니다.

[전체 실습 안내](../readme.md) · [DB 공통 준비](../00.Setup.md)
