# OL9 Intel CPU vLLM 인터넷 연결 설치 가이드

기준일 2026년 11월 11일  |  문서 버전 1.0  |  CPU 전용

Oracle Linux 9의 Intel x86_64 CPU 서버에 vLLM과 소형 모델을 설치하고, OpenAI 호환 API를 systemd 서비스로 운영하는 절차다. NVIDIA 드라이버와 CUDA는 설치하지 않는다. 명령은 관리자 권한이 있는 opc 또는 동등한 계정으로 Bash에서 실행한다. 각 코드 블록이 성공한 뒤 다음 단계로 진행한다.

### 기준 구성

| 항목 | 기준 |
| --- | --- |
| 운영체제 | Oracle Linux 9.8 x86_64 기준  다른 OL9는 사전 확인 |
| CPU | Intel AVX512 지원 CPU  BF16 명령어 지원 시 우선 활용 |
| Python | 3.12 계열  설치된 패치 버전을 기록 |
| vLLM | 0.29.0+cpu  manylinux_2_34_x86_64 wheel |
| 모델 | Qwen2.5-0.5B-Instruct  BF16  검증용 |
| API | 127.0.0.1 포트 8000  모델 별칭 qwen-test |

### 적용 범위와 검증 이력

프로젝트에서 확인한 결과는 OL9.8 AMD EPYC VM에서 vLLM 0.29.0+cpu, PyTorch 2.13.0+cpu, Qwen2.5-0.5B-Instruct의 API 응답 성공이다. 이 문서는 Intel용으로 경로와 운영 절차를 정리한 것이며 Intel 실기 검증 완료를 뜻하지 않는다. Intel 대상 서버의 CPU 명령어, 패키지 의존성, 서비스 기동과 실제 응답을 본문의 기준으로 검증한다.

초기 검증은 현재 프로젝트의 1코어 2스레드와 약 11GiB RAM에서 시작했다. Intel 계획값으로는 4개 이상의 물리 코어와 16GiB 이상 RAM을 권장하되 성능 보장은 아니다. 모델 확대와 동시 요청 수는 실측 후 조정한다. 설치 대상 /opt와 임시 다운로드 영역에 각각 충분한 공간을 확보한다. 준비 서버는 wheel과 RPM 복제로 공간이 더 필요하므로 40GiB 이상의 여유 공간을 계획하고 실제 번들 크기로 재산정한다.

## 1 사전 점검과 OS 패키지

```bash
cat /etc/oracle-release
uname -m
getconf GNU_LIBC_VERSION
LC_ALL=C lscpu
free -h
df -h / /opt /var
```

합격 기준은 x86_64, GenuineIntel, avx512f 플래그다. glibc는 2.34 이상이어야 기준 wheel을 사용할 수 있다. avx512_bf16이 없는 Intel CPU는 BF16 성능이 다를 수 있으므로 반드시 실측한다. BF16 커널 오류가 나면 DTYPE=float32로 검증하고 메모리 사용량을 다시 측정한다. AVX512가 없는 서버는 이 가이드의 표준 경로에서 제외하고 별도의 AVX2 빌드 또는 실행 경로를 검증한다. [^1][^2]

lscpu의 모델명에 표시되는 전체 칩 코어 수와 VM에 할당된 코어 수는 다를 수 있다. Core(s) per socket, Socket(s), Thread(s) per core와 실제 CPU 목록으로 계산한다. 하이퍼스레드 두 개를 물리 코어 두 개로 계산하지 않는다.

### 경로와 권한

/opt/vllm/venv는 전용 가상환경, /opt/vllm/models는 모델, /opt/vllm/cache는 컴파일 및 라이브러리 캐시다. /etc/vllm/vllm.env와 /opt/vllm/bin/start-vllm.sh는 root가 관리한다. vllm 계정은 런타임과 캐시를 사용한다. 이 절차는 새 설치 기준이다. 기존 서비스가 있으면 설정과 모델을 백업하고 별도 경로에서 검증한다.

SELinux는 활성 상태를 유지한다. 권한 문제가 발생하면 journal과 AVC 기록으로 원인을 확인하며 SELinux를 일괄 비활성화하지 않는다. 외부 접속 구성은 API 검증 후 적용한다.

### 필수 OS 패키지 설치

```bash
sudo dnf install -y curl jq ca-certificates tar gzip \
  libgomp numactl numactl-libs make \
  gcc-toolset-14-gcc gcc-toolset-14-gcc-c++
/opt/rh/gcc-toolset-14/root/usr/bin/g++ --version
```

GCC Toolset 14는 AppStream 저장소에서 제공된다. 패키지를 찾지 못하면 dnf repolist로 ol9_appstream과 기본 OL9 저장소 활성 상태를 확인한다. 인터넷 통신에는 GitHub 릴리스와 자산 배포 호스트, PyPI 배포 호스트, download.pytorch.org, Hugging Face와 실제 모델 다운로드 호스트가 필요하다. 프록시 환경은 조직 프록시와 CA를 설정하며 TLS 검증을 끄지 않는다. [^3]

## 2 전용 계정과 Python 준비

```bash
getent passwd vllm || sudo useradd --system \
  --home-dir /opt/vllm --shell /sbin/nologin vllm
sudo install -d -o vllm -g vllm /opt/vllm
sudo install -d -o vllm -g vllm \
  /opt/vllm/models /opt/vllm/cache /opt/vllm/records
sudo install -d -o root -g root /opt/vllm/bin /etc/vllm
```

관리 계정에 uv를 설치한 다음 실행 파일을 /usr/local/bin에 배치한다. 서비스용 Python은 OS Python과 분리해 /opt/vllm/runtimes 아래에 설치한다. [^4]

```bash
curl -fLsS https://astral.sh/uv/install.sh \
  -o /tmp/vllm-uv-install.sh
sh /tmp/vllm-uv-install.sh
sudo install -m 755 "$HOME/.local/bin/uv" /usr/local/bin/uv
/usr/local/bin/uv --version

sudo -u vllm env \
  UV_PYTHON_INSTALL_DIR=/opt/vllm/runtimes \
  UV_CACHE_DIR=/opt/vllm/cache/uv \
  /usr/local/bin/uv venv /opt/vllm/venv \
  --python 3.12 --managed-python --seed

sudo -u vllm /opt/vllm/venv/bin/python --version
```

uv는 Python 3.12 런타임을 다운로드한다. seed 옵션으로 pip를 포함한다. 가상환경을 서버 간에 그대로 복사하지 않는다. 폐쇄망에서는 Python 런타임을 반입한 후 최종 경로에서 새 가상환경을 생성한다.

## 3 CPU 전용 vLLM 패키지 설치

실제 프로젝트에서 설치와 API 응답을 확인한 0.29.0+cpu의 manylinux_2_34_x86_64 파일을 사용한다. 최신 릴리스는 사전 릴리스이거나 glibc 2.39를 요구할 수 있으므로 자동 선택하지 않는다. Python 의존 패키지는 아래 설치 시점에 결정되므로 성공 후 버전을 반드시 고정한다.

```bash
RELEASE_BASE='https://github.com/vllm-project/vllm/releases/download'
WHEEL='vllm-0.29.0%2Bcpu-cp38-abi3-manylinux_2_34_x86_64.whl'
VLLM_WHEEL_URL="$RELEASE_BASE/v0.29.0/$WHEEL"
sudo -u vllm env UV_CACHE_DIR=/opt/vllm/cache/uv \
  /usr/local/bin/uv pip install \
  --python /opt/vllm/venv/bin/python \
  "$VLLM_WHEEL_URL" --torch-backend cpu

sudo -u vllm /opt/vllm/venv/bin/python -m pip check
```

pip check가 의존성 충돌을 보고하면 운영 등록을 중단하고 해당 조합을 다시 확인한다. pip install vllm만 실행하면 CPU wheel이 선택된다는 보장이 없으므로 사용하지 않는다.

### 로딩 확인

```bash
sudo -u vllm bash <<'SH'
set -euo pipefail
IOMP=$(find /opt/vllm/venv -name libiomp5.so -print -quit)
test -n "$IOMP"
export LD_PRELOAD="$IOMP${LD_PRELOAD:+:$LD_PRELOAD}"
/opt/vllm/venv/bin/python - <<'PY'
import torch, vllm
from vllm.platforms import current_platform
print('vLLM:', vllm.__version__)
print('PyTorch:', torch.__version__)
print('CUDA build:', torch.version.cuda)
print('Platform:', type(current_platform).__name__)
PY
SH
```

vLLM 0.29.0+cpu, CUDA build None, CpuPlatform을 확인한다. Triton 비활성화 경고만으로 실패로 판정하지 않는다.

## 4 모델 다운로드와 설치 기록

Hugging Face에서 모델 commit을 조회하고 해당 revision으로 다운로드한다. 설정, tokenizer, 가중치와 라이선스 파일을 함께 보관한다. 가중치는 약 1GB 수준이며 캐시와 임시 파일을 위한 추가 공간이 필요하다. [^5][^6]

```bash
sudo -u vllm env HF_HOME=/opt/vllm/cache/huggingface \
  /opt/vllm/venv/bin/python - <<'PY'
from pathlib import Path
from huggingface_hub import HfApi, snapshot_download
repo = 'Qwen/Qwen2.5-0.5B-Instruct'
revision = HfApi().model_info(repo).sha
snapshot_download(
    repo_id=repo, revision=revision,
    local_dir='/opt/vllm/models/Qwen2.5-0.5B-Instruct',
    allow_patterns=['*.json', '*.safetensors', '*.txt',
                    '*.model', '*.jinja', '*.md', 'LICENSE*'],
)
Path('/opt/vllm/records/model-revision.txt').write_text(
    repo + '\n' + revision + '\n')
print('Downloaded revision:', revision)
PY
```

### 의존 패키지와 시스템 정보 기록

```bash
sudo -u vllm bash <<'SH'
set -euo pipefail
/opt/vllm/venv/bin/python -m pip list --format=freeze \
  > /opt/vllm/records/requirements.lock
/opt/vllm/venv/bin/python --version \
  > /opt/vllm/records/python-version.txt
cat /etc/oracle-release > /opt/vllm/records/os-release.txt
LC_ALL=C lscpu > /opt/vllm/records/lscpu.txt
rpm -qa | sort > /opt/vllm/records/rpm-list.txt
SH
```

requirements.lock은 설치된 전체 패키지의 name==version 목록이다. URL 기반 freeze 항목 대신 버전 목록을 저장하므로 폐쇄망에서 원격 URL을 다시 조회하지 않고 wheelhouse로 재설치할 수 있다. 이 목록만으로 파일이 반입되는 것은 아니다.

## 5 서비스 환경 설정

아래 환경 파일은 인터넷 연결 여부와 관계없이 로컬 모델만 사용하도록 설정한다. 추론 스레드 1개와 KV 캐시 1GiB는 최초 검증값이다. 변경 후 서비스를 재시작한다. [^1][^7]

```bash
sudo tee /etc/vllm/vllm.env >/dev/null <<'EOF'
MODEL_DIR=/opt/vllm/models/Qwen2.5-0.5B-Instruct
SERVED_MODEL_NAME=qwen-test
LISTEN_HOST=127.0.0.1
PORT=8000
DTYPE=bfloat16
MAX_MODEL_LEN=2048
MAX_NUM_SEQS=1
VLLM_CPU_KVCACHE_SPACE=1
VLLM_CPU_OMP_THREADS_BIND=nobind
OMP_NUM_THREADS=1
HF_HOME=/opt/vllm/cache/huggingface
HF_HUB_OFFLINE=1
TRANSFORMERS_OFFLINE=1
HF_HUB_DISABLE_TELEMETRY=1
VLLM_NO_USAGE_STATS=1
DO_NOT_TRACK=1
TORCHINDUCTOR_CACHE_DIR=/opt/vllm/cache/inductor
VLLM_CACHE_ROOT=/opt/vllm/cache/vllm
EOF
sudo chown root:vllm /etc/vllm/vllm.env
sudo chmod 640 /etc/vllm/vllm.env
```

BF16은 모델 가중치의 자료형이다. MAX_MODEL_LEN은 입력과 출력의 전체 토큰 한도이며 MAX_NUM_SEQS는 동시에 처리할 시퀀스 수다. VLLM_CPU_KVCACHE_SPACE는 프로세스별 KV 캐시 GiB 값이다. 모델 가중치와 캐시 외에도 Python, 연산 작업공간과 OS 메모리가 필요하다.

HF_HUB_OFFLINE과 TRANSFORMERS_OFFLINE은 모델 라이브러리의 외부 조회를 막는 설정이다. 호스트 전체의 통신을 차단하는 방화벽 기능은 아니므로 폐쇄망 검증에는 별도의 통신 차단이 필요하다.

## 6 서비스 실행 스크립트

systemd는 로그인 셸의 가상환경과 GCC 설정을 상속하지 않는다. 실행 스크립트에서 GCC Toolset과 OpenMP를 매번 설정한다. Intel OpenMP는 CPU용 vLLM 의존 패키지에 포함된다. [^1][^3]

```bash
sudo tee /opt/vllm/bin/start-vllm.sh >/dev/null <<'SH'
#!/bin/bash
set -eo pipefail
source /opt/rh/gcc-toolset-14/enable
set -u
export CC=/opt/rh/gcc-toolset-14/root/usr/bin/gcc
export CXX=/opt/rh/gcc-toolset-14/root/usr/bin/g++
export PATH="/opt/vllm/venv/bin:$PATH"
export VIRTUAL_ENV=/opt/vllm/venv
IOMP_PATH=$(find /opt/vllm/venv \
  -name libiomp5.so -print -quit)
if [[ -z "$IOMP_PATH" ]]; then
  echo 'ERROR: libiomp5.so not found' >&2
  exit 1
fi
export LD_PRELOAD="$IOMP_PATH${LD_PRELOAD:+:$LD_PRELOAD}"
exec /opt/vllm/venv/bin/vllm serve "$MODEL_DIR" \
  --served-model-name "$SERVED_MODEL_NAME" \
  --dtype "$DTYPE" \
  --host "$LISTEN_HOST" --port "$PORT" \
  --max-model-len "$MAX_MODEL_LEN" \
  --max-num-seqs "$MAX_NUM_SEQS"
SH
sudo chown root:root /opt/vllm/bin/start-vllm.sh
sudo chmod 755 /opt/vllm/bin/start-vllm.sh
```

컴파일러 설치 후에도 InvalidCxxCompiler가 발생하면 서비스 환경의 CXX 경로와 실행 권한을 확인한다. libiomp5.so가 없으면 패키지 설치가 완전한지 확인한다. 이 스크립트는 환경 파일을 직접 읽지 않으며 systemd의 EnvironmentFile로 전달받는다.

## 7 systemd 등록과 자동 시작

이전 테스트 서버가 포트 8000을 사용 중이면 해당 터미널에서 Ctrl+C로 종료한다. 서비스는 vllm 계정으로 실행되고 로그는 journal에 기록된다. 실행 중인 journal 조회는 Ctrl+C로 종료해도 서비스가 계속 실행된다.

```bash
sudo tee /etc/systemd/system/vllm-cpu.service >/dev/null <<'EOF'
[Unit]
Description=vLLM CPU inference API
After=network.target
StartLimitIntervalSec=600
StartLimitBurst=3

[Service]
Type=simple
User=vllm
Group=vllm
WorkingDirectory=/opt/vllm
Environment=HOME=/opt/vllm
EnvironmentFile=/etc/vllm/vllm.env
ExecStart=/opt/vllm/bin/start-vllm.sh
Restart=on-failure
RestartSec=15
TimeoutStopSec=120
KillSignal=SIGTERM
LimitNOFILE=65536
UMask=0027
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
sudo systemd-analyze verify \
  /etc/systemd/system/vllm-cpu.service
sudo systemctl daemon-reload
sudo systemctl enable --now vllm-cpu.service
sudo journalctl -u vllm-cpu.service -f
```

Application startup complete 이후 API를 검증한다. active 표시는 프로세스가 실행 중이라는 뜻이며 API 준비 완료를 보장하지 않는다. 초기 CPU 컴파일은 수분 이상 걸릴 수 있다. 반복 실패 제한에 걸리면 원인을 고친 뒤 systemctl reset-failed vllm-cpu.service와 systemctl start vllm-cpu.service를 실행한다.

## 8 API 검증과 운영 인수

별도 터미널에서 다음 요청을 실행한다. health는 HTTP 200과 빈 본문이 정상일 수 있다. 모델 목록에 qwen-test가 표시되고 추론 응답의 choices[0].message.content에 생성된 문자열이 있어야 한다.

```bash
curl -fsS http://127.0.0.1:8000/health
curl -fsS http://127.0.0.1:8000/v1/models \
  | python3 -m json.tool --no-ensure-ascii
curl -fsS http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen-test",
    "messages": [
      {"role": "user", "content": "한 문장으로 자기소개해 주세요."}
    ],
    "max_tokens": 64,
    "temperature": 0
  }' | python3 -m json.tool --no-ensure-ascii
```

finish_reason이 stop이면 정상 종료다. length이면 출력 토큰 한도에 도달한 것으로 반드시 장애는 아니다. 한글의 유니코드 이스케이프는 JSON 표현이며 --no-ensure-ascii 옵션으로 읽기 쉽게 표시할 수 있다.

```bash
sudo systemctl status vllm-cpu.service --no-pager
sudo journalctl -u vllm-cpu.service -n 100 --no-pager
sudo systemctl restart vllm-cpu.service
sudo systemctl stop vllm-cpu.service
sudo systemctl start vllm-cpu.service
```

인수 조건은 패키지 검사 통과, CPU 플랫폼 확인, health 200, 모델 목록과 추론 응답 정상, 서비스 재시작 후 API 정상, 재부팅 후 자동 시작과 API 정상이다. 운영 재부팅은 승인된 점검 시간에 수행한다. Qwen 0.5B는 설치 검증용이며 한국어 답변 품질이나 운영 처리량의 기준 모델로 간주하지 않는다.

## 9 운영 조정과 장애 대응

증설 후 lscpu와 free -h로 실제 자원을 다시 확인한다. 물리 코어 수와 CPU 배치를 기준으로 OMP_NUM_THREADS를 늘리되 API 처리를 위한 여유를 남긴다. 현재 nobind 설정은 초기 검증용이다. 다중 코어 또는 NUMA 서버는 코어 바인딩과 NUMA별 메모리를 따로 튜닝한다. 같은 프롬프트와 출력 길이로 단일 요청 지연, 동시 요청 처리량, RAM과 CPU 사용률을 비교한다.

변경 순서는 CPU 증설과 스레드 조정, 모델 크기 변경, 컨텍스트와 동시 요청 확대다. 한 번에 한 항목씩 바꾸고 API 검증을 반복한다. 모델 변경 시 MODEL_DIR와 SERVED_MODEL_NAME을 함께 확인한다. 패키지 업그레이드는 새 가상환경에서 검증한 뒤 전환한다.

| 증상 | 원인과 조치 |
| --- | --- |
| wheel 다운로드 404 | 파일명을 추측하지 말고 릴리스의 실제 asset URL 확인 |
| manylinux_2_39 불일치 | OL9 glibc 2.34에 맞는 wheel 사용  기준 파일은 2_34 |
| InvalidCxxCompiler | GCC Toolset 14 설치와 서비스 스크립트의 CC 및 CXX 확인 |
| Triton 비활성화 경고 | CPU 경로에서는 예상 안내  뒤따르는 실제 예외를 확인 |
| libiomp5.so 로딩 실패 | intel-openmp 설치와 LD_PRELOAD 경로 및 권한 확인 |
| 프로세스 종료와 OOM | journal 및 커널 로그 확인  캐시와 동시 요청 축소 또는 RAM 증설 |
| Address already in use | 기존 foreground 서버와 systemd 서비스의 포트 중복 확인 |
| BF16 연산 실패 | CPU 플래그와 커널 호환 확인  float32로 분리 검증 후 메모리 재산정 |
| 모델 파일 조회 실패 | 로컬 경로와 가중치 및 tokenizer 파일 누락 확인 |

```bash
sudo journalctl -u vllm-cpu.service -n 150 --no-pager
sudo journalctl -k --since '-15 min' --no-pager
sudo ss -ltnp 'sport = :8000'
sudo -u vllm /opt/vllm/venv/bin/python -m pip check
```

## 10 접속 구성과 참고 자료

기본 API는 VM 내부에서만 접근한다. 관리 PC에서 접속할 때는 SSH 터널을 사용할 수 있다. 다음 VM_IP는 서버 주소로 바꾼다. 로컬 포트 충돌 시 앞의 8000을 다른 포트로 바꾼다.

```bash
ssh -N -L 8000:127.0.0.1:8000 opc@VM_IP
```

내부 서비스로 공개할 때는 LISTEN_HOST를 사설 IP 또는 0.0.0.0으로 변경하고 서비스를 재시작한다. OS 방화벽과 OCI NSG 또는 보안 목록의 TCP 8000 접근을 필요한 사설 클라이언트 대역으로 제한한다. 인증과 TLS가 필요한 경우 앞단 프록시 또는 API Gateway에 연결하고 클라이언트에서 API를 다시 검증한다.

인터넷용 최신 버전 자동 선택 명령은 운영 설치에서 사용하지 않는다. vLLM wheel과 Python 패치 버전, 전체 의존 패키지, 모델 commit, RPM 목록, 설정 파일을 하나의 배포 단위로 보관한다. 새 모델 또는 버전은 호환성을 다시 확인한다.

### 공식 참고 자료

[^1]: [vLLM 0.29 CPU 설치 및 실행](https://docs.vllm.ai/en/v0.29.0/getting_started/installation/cpu/)

[^2]: [Python wheel 플랫폼 태그](https://packaging.python.org/en/latest/specifications/platform-compatibility-tags/)

[^3]: [Oracle Linux GCC Toolset 14](https://docs.oracle.com/en/operating-systems/oracle-linux/9/relnotes9.5/ol9-features-CompilersandDevTools.html)

[^4]: [uv 설치와 Python 관리](https://docs.astral.sh/uv/guides/install-python/)

[^5]: [Qwen 공식 모델](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)

[^6]: [모델 다운로드](https://huggingface.co/docs/huggingface_hub/guides/download)

[^7]: [Hugging Face 오프라인 환경변수](https://huggingface.co/docs/huggingface_hub/package_reference/environment_variables)

[^8]: [pip download](https://pip.pypa.io/en/stable/cli/pip_download/)

[^9]: [DNF 의존 RPM 다운로드](https://dnf-plugins-core.readthedocs.io/en/latest/download.html)
