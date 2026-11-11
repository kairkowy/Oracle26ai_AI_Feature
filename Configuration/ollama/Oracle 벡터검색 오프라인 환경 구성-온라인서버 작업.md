## Oracle 벡터 검색 환경 설정을 위한 온라인 서버 작업 가이드

오프라인(인터넷 액세스 불가) 환경에서 오라클 벡터검색 환경구성을 위한 가이드 문서입니다. 오라클 사용자 가이드 매뉴얼 내용은 인터넷 온라인 환경을 기준으로 기술되어 있어서 오프라인 환경의 작업을 위해서는 개별적인 추가 작업 기술이 필요합니다. 이러한 부분에서 온라인, 오프라인 작업자의 작업을 돕기 위하여 관련 내용을 정리하게 되었습니다.

### 1. Oracle Linux (8.10) 다운로드 및 준비

VMware 상에서 OL8.10 설치하는 방법을 기술하였습니다.

https://yum.oracle.com/oracle-linux-isos.html 에서 Full ISO 파일을 다운로드하여 이동 저장매체에 저장합니다.

오프라인 환경에 다운로드 파일을 이동해서 가상환경의 미디어 환경에 마운트시킵니다.

VMware 가상머신에서 ISO file을 이용한 OL8.10을 설치하는 방법을 사용하여 OS를 설치합니다.


### 2. 오라클 Instant Client for linux 다운로드 및 준비

2.1 온라인 서버에서 기본 라이브러리(libaio) 패키지 다운로드 

온라인 OL8.10 서버 환경에서 다음과 같이 진행합니다. 

```
su - root 
mkdir -p /tmp/libaio_rpms
cd /tmp/libaio_rpms
dnf download --resolve --arch=x86_64 libaio libaio-devel    
cd /tmp
tar cvf libaio_rpms.tar libaio_rpms

```
libaio_rpms.tar 파일을 오프라인 서버로 이동(미디어 사용)

2.2  Oracle Instant Client 패키지 다운로드

https://www.oracle.com/kr/database/technologies/instant-client/downloads.html 에서 사용자 OS 환경을 선택하고, 필요한 버전에서 RPM 또는 바이너리 패키지를 다운로드합니다. 이 문서에서는 바이너리 패키지를 사용합니다.

다운로드 리스트

  * 기본패키지 : instantclient-basic-linux.x64-23.26.0.0.0.zip
  * SQLPLUS 패키지 : instantclient-sqlplus-linux.x64-23.26.0.0.0.zip
  * Tools 패키지 : instantclient-tools-linux.x64-23.26.0.0.0.zip

zip 파일을 오프라인 서버 /tmp 로 이동

### 3. 파이썬 필수 라이브러리 다운로드 및 패키징 

3.1 파이썬 라이브러리 다운로드

온라인 서버에서 다음을 진행합니다.

```
su- root

mkdir /tmp/python_rpms_no_tk

dnf config-manager --set-enabled ol8_codeready_builder
dnf clean all && dnf makecache

cd /tmp/python_rpms_no_tk

dnf download --resolve --arch=x86_64,noarch \
  libffi-devel \
  openssl openssl-devel openssl-libs \
  xz-devel \
  zlib-devel \
  bzip2-devel bzip2-libs \
  readline-devel \
  libuuid-devel \
  ncurses-devel ncurses-libs ncurses-c++-libs \
  libaio \
  tk tk-devel tcl-devel \
  libX11 libX11-xcb libX11-devel \
  libXft libXft-devel \
  xorg-x11-proto-devel \
  libxcb libxcb-devel \
  libXrender libXrender-devel \
  fontconfig fontconfig-devel \
  freetype freetype-devel

rm -f tk-*.rpm tk-devel-*.rpm tcl-devel-*.rpm \
      libX*.rpm libxcb*.rpm libXrender*.rpm \
      fontconfig*.rpm freetype*.rpm \
      *proto*.rpm xorg*-proto*.rpm

cd /tmp
tar cvf python_rpms_no_tk.tar python_rpms_no_tk
```
오프라인 서버로 python_rpms_no_tk.tar 파일 이동

3.2 sqlite 다운로드 

오프라인 서버에서 다음과 같이 실행했는데 에러가 나면 sqlite3를 설치해야합니다.
```
python -c "import sqlite3"

ModuleNotFoundError: No module named '_sqlite3' 에러 발생시 sqlite3-devel 설치 후 python 부터 재설치를 진행하세요. 
```

온라인 서버에서 다음과 같이 진행합니다.

```
su - root

dnf install -y dnf-plugins-core

mkdir -p /tmp/sqlite_rpms
cd /tmp/sqlite_rpms

dnf download --resolve --arch=x86_64 sqlite sqlite-libs sqlite-devel

cd /tmp

tar cvf sqlite_rpms.tar sqlite_rpms
```
sqlite_rpms.tar 파일을 오프라인 서버의 /tmp 로 이동


3.3 파이썬 소스 다운로드

파이썬 사이드에서 필요한 버전의 소스 파일을 다운로드하고 오프라인서버의 /opt/python으로 이동합니다.

https://www.python.org/downloads/release/python-3126/


### 4. pip 업그레이드 패키지 다운로드 및 준비

온라인 서버에서

```
su - 계정명

mkdir -p $HOME/pip_offline
cd pip_offline

python3 -m pip download --only-binary=:all: pip

ls 
pip-25.3-py3-none-any.whl
```
pip-25.3-py3-none-any.whl 파일을 오프라인 서버로 이동

### 5. 오라클 벡터검색 기본 라이브러리 다운로드 및 준비

온라인 서버에서 다음과 같이 준비합니다. 아래 wheel들은 23.26에서 기본 적으로 필요한 라이브러리 셋입니다.

```

su - dev01

mkdir -p /tmp/def_whl
tee /tmp/def_whl/def_whl.txt<<EOF
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
EOF

cd /tmp/def_whl

python -m pip download -r def_whl.txt -d /tmp/def_whl --only-binary=:all: --prefer-binary

cd /tmp
tar cvf def_whl.tar def_whl
```
def_whl.tar 파일을 오프라인 서버의 /tmp 로 이동합니다.

### 6. OML4py client 라이브러리 다운로드 및 준비

오라클 oml4py 클라이언트 다운로드에서 DB 버전에 맞는 패키지를 다운로드합니다.

https://www.oracle.com/database/technologies/oml4py-downloads.html

오프라인 서버로 V1048628-01.zip 파일 /opt/oracle/oml4py 로 이동합니다.

### 7. jupyter lab 다운로드 및 준비

온라인 서버에서 다음과 같이 패키징 작업을 합니다.

``` 
su - 유저

mkdir -p /tmp/jupyterlab_wheelhouse

cd /tmp
python -m pip download -d ./jupyterlab_wheelhouse jupyterlab

tar cvf jupyterlab_wheelhouse.tar jupyterlab_wheelhouse
```
jupyterlab_wheelhouse.tar 파일을 오프라인 서버 /tmp로 이동

### 8. 오라클 제공 임베딩 모델 다운로드

오라클23ai가 설치되어 있는 온라인 서버에서 다음과 같이 작업합니다.

 ```python
python
import oml
import oracledb
oml.core.methods.__embed__ = False

connection = oracledb.connect(user="labadmin", password="labadmin", dsn="dbserver26ai:1521/freepdb1")
cursor = connection.cursor()

# 버전 확인
dbversion = """select product,VERSION_FULL from product_component_version"""
result=cursor.execute(dbversion).fetchall()
print('DB version : ',result)

OUT : DB version :  [('Oracle AI Database 26ai Free', '23.26.0.0.0')]

from oml.utils import ONNXPipeline,ONNXPipelineConfig
ONNXPipelineConfig.show_preconfigured()
out: 
['sentence-transformers/all-mpnet-base-v2',
 'sentence-transformers/all-MiniLM-L6-v2',
 'sentence-transformers/multi-qa-MiniLM-L6-cos-v1',
 'sentence-transformers/distiluse-base-multilingual-cased-v2',
 'sentence-transformers/all-MiniLM-L12-v2',
 'BAAI/bge-small-en-v1.5',
 'BAAI/bge-base-en-v1.5',
 'taylorAI/bge-micro-v2',
 'intfloat/e5-small-v2',
 'intfloat/e5-base-v2',
 'thenlper/gte-base',
 'thenlper/gte-small',
 'TaylorAI/gte-tiny',
 'sentence-transformers/paraphrase-multilingual-mpnet-base-v2',
 'intfloat/multilingual-e5-base',
 'intfloat/multilingual-e5-small',
 'sentence-transformers/stsb-xlm-r-multilingual',
 'Snowflake/snowflake-arctic-embed-xs',
 'Snowflake/snowflake-arctic-embed-s',
 'Snowflake/snowflake-arctic-embed-m',
 'mixedbread-ai/mxbai-embed-large-v1',
 'openai/clip-vit-large-patch14',
 'google/vit-base-patch16-224',
 'microsoft/resnet-18',
 'microsoft/resnet-50',
 'WinKawaks/vit-tiny-patch16-224',
 'Falconsai/nsfw_image_detection',
 'WinKawaks/vit-small-patch16-224',
 'nateraw/vit-age-classifier',
 'rizvandwiki/gender-classification',
 'AdamCodd/vit-base-nsfw-detector',
 'trpakov/vit-face-expression',
 'BAAI/bge-reranker-base']

# pretrained & preconfig ONNX 모델 다운로드
# 위 임베딩 모델 리스트에서 필요 또는 모든 모델을 다운로드합니다.

config   = ONNXPipelineConfig.from_template("text", max_seq_length=256,
           distance_metrics=["COSINE"], quantize_model=True)
pipeline = ONNXPipeline(model_name="intfloat/multilingual-e5-small",config=config)
pipeline.export2file("multilingual_e5_small", output_dir=".")
print("complete export2file")
```
다운로드 된 ONNX 모델을 오프라인 DB서버 /u01/models로 이동합니다.

### 9. RAG 환경을 위한 ollama 준비

Ollama 오프라인 설치, LLM 모델 다운로드 및 오프라인 이동 방법은 아래 링크를 참고하세요.
https://github.com/kairkowy/handon-labs-for-vector-search/blob/main/similarity_search/OLLAMA%20%EC%98%A4%ED%94%84%EB%9D%BC%EC%9D%B8%20%EC%84%A4%EC%B9%98%20%EB%B0%8F%20RPM%20%EC%84%A4%EC%B9%98%20%EB%B0%A9%EB%B2%95.md

