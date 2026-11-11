### Ollama 오프라인 설치 절차(Oracle Linux 8/9)

STEP 1 — 온라인 PC에서 바이너리 다운로드

  다운로드: https://github.com/ollama/ollama/releases

  예: ollama-linux-amd64.tgz

STEP 2 — 바이너리를 오프라인 서버에 전달

  ollama-linux-amd64.tgz 복제 

STEP 3 — 압축 해제 및 설치

root 계정에 설치 :

```
cd /tmp
sudo tar zx -C /usr -f ollama-linux-amd64.tgz

ollama serve
ollama -v

-- Ollama servie startup 위한 Ollama 유저 생성

sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
sudo usermod -a -G ollama $(whoami)
```

일반 계정에 설치 :

```
tar -xvf ollama.tgz
mkdir -p ~/bin
mv ollama ~/bin/
chmod +x ~/bin/ollama

echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

ollama serve
ollama --version
```

STEP 4 - 서버 부팅시 자동실행 원하는 경우:

STEP 4.1 일반계정 설치
서비스 파일 만들기 :
```
mkdir -p ~/.config/systemd/user
tee ~/.config/systemd/user/ollama.service <<EOF
[Unit]
Description=Ollama Server (User Mode)

[Service]
ExecStart=%h/bin/ollama serve
Restart=always
RestartSec=3
Environment="PATH=$PATH"
Environment=OLLAMA_MODELS=/var/lib/ollama/.ollama/models  -- 수정
Environment="OLLAMA_HOST=0.0.0.0"
[Install]
WantedBy=default.target
EOF
  
--서비스 리로드
systemctl --user daemon-reload

--서비스 시작
systemctl --user start ollama

--부팅시 자동 실
systemctl --user enable ollama

--서비스 상태 확인
systemctl --user status ollama

```

STEP 4.2 root 계정 설치

서비스 파일 생성 :

```
sudo tee /etc/systemd/system/ollama.service <<EOF
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=$PATH"
Environment=OLLAMA_MODELS=/var/lib/ollama/.ollama/models  -- 수정
Environment="OLLAMA_HOST=0.0.0.0"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ollama
```


STEP 5 - 모델 설치(오프라인 환경에서 가장 중요)

STEP 5.1 Ollama Library에서 다운로드하고 tar로 모으기

```
인터넷 서버 ollama 환경에서

ollama pull 모델명  -- 실행
ollama list         -- 다운로드 리스트 확인

다운로드 위치
$HOME/.ollama/models 
    blobs
    manifests

cd $HOME/.ollama/
tar -cvf ollama-models.tar models

ollama-models.tar를 저장매체에 복사
```

STEP 5.1 tar 파일을 오프라인 서버의 ollama 계정으로 이동
    
일반 계정에 서비스 설치한 경우 :
```
-- tar 파일 풀기

cd $HOME/.ollama
cp media/ollama-models.tar . 
tar -xvf ollama-models.tar

ollama run llama3
```

root 계정에 설치한 경우 :
```
-- tar 파일 풀기
sudo cd /usr/share/ollama/.ollama
sudo cp media/ollama-models.tar . 
sudo tar -xvf ollama-models.tar

ollama list
ollama run llama3
```

STEP 6 - 기타(Huggingface) 서비스 플랫폼에서 모델 다운로드

예: Llama 3.1 q4 model(gguf 파일)

온라인 서버에서 다운로드:

```
export HF_TOKEN=토큰

wget --header="Authorization: Bearer $HF_TOKEN" https://huggingface.co/karpathy/Llama3-gguf/resolve/main/Llama3-8B-Instruct-Q4_K_M.gguf -O Llama3-8B-Instruct-Q4_K_M.gguf
```
오프라인 서버로 파일 전달 후:

오프라인 서버에서 Modelfile 생성하여 설치:

```
Modelfile 작성:
tee ./Modelfile<<EOF
FROM ./llama3.gguf
TEMPLATE """{{ .Prompt }}"""
EOF

ollama create llama3-offline -f Modelfile

ollama run llama3-offline
```

기타. Oracle Linux 오프라인 설치 시 필요한 RPM 라이브러리

1. 의존 패키지 목록(최소)
구분	패키지
컴파일/런타임	glibc, glibc-devel, gcc, gcc-c++, make
압축/네트워크	zlib, zlib-devel, openssl, openssl-devel, curl
BLAS(선택)	openblas, openblas-devel
GPU 사용 시	(NVIDIA 또는 ROCm 패키지)

2. 의존 패키지 다운로드 명령(온라인 서버에서)

```
sudo dnf download \
  --resolve \
  --alldeps \
  --downloaddir=$(pwd) \
  glibc glibc-devel gcc gcc-c++ make zlib zlib-devel openssl openssl-devel curl

```
3. 생성된 /tmp/ollama_rpms/*.rpm 파일을 오프라인 서버로 복사한 후:


오프라인 서버 설치:

```
인스톨 서버
mkdir ollama_rpms

rpm셋 복제

cd /ollama_rpms

sudo dnf localinstall -y *.rpm

```
4. GPU 없는 경우(오프라인 서버 CPU-only)

Ollama는 CPU 모드로도 잘 작동함.

필요 의존 패키지는 위 RPM 목록으로 충분함.

5. GPU 있는 경우(오프라인 NVIDIA 서버)
(1) NVIDIA Driver + CUDA 오프라인 패키지 다운로드

온라인 PC에서 다음 파일 다운로드:

NVIDIA CUDA Offline installers
https://developer.nvidia.com/cuda-downloads

예:
cuda_12.6.0_520.61_linux.run

오프라인 서버에서 설치:
```
sudo sh cuda_12.6.0_520.61_linux.run

확인:

nvidia-smi
```
Ollama는 자동으로 GPU 모드로 실행됨.
