# OL9 Intel CPU vLLM 설치와 모델 서비스

Oracle Linux 9의 Intel x86_64 CPU 환경에서 vLLM을 설치하고 모델을 OpenAI 호환 API로 서비스하는 가이드입니다.

| 환경 | 가이드 | 주요 내용 |
| --- | --- | --- |
| 인터넷 연결 | [인터넷 연결 설치 가이드](ONLINE_INSTALL.md) | 사전 점검, Python과 CPU wheel 설치, 모델 다운로드, systemd 등록, API 검증 |
| 폐쇄망 | [폐쇄망 설치 가이드](OFFLINE_INSTALL.md) | RPM과 전체 wheel 수집, Python과 모델 반입, 해시 검증, 로컬 설치, systemd 등록, 망 차단 검증 |

## 기준 구성

- OS: Oracle Linux 9.8 x86_64 기준
- CPU: Intel AVX512 지원 CPU, BF16 지원 여부 별도 점검
- Python: 3.12 계열
- vLLM: `0.29.0+cpu`, `manylinux_2_34_x86_64` wheel
- 검증용 모델: `Qwen/Qwen2.5-0.5B-Instruct`
- 기본 API: `http://127.0.0.1:8000`, 모델 별칭 `qwen-test`

## 검증 범위

프로젝트에서 실제 성공한 구성은 OL9.8 AMD EPYC VM의 CPU 전용 설치와 모델 API 응답입니다. 이 가이드는 해당 결과와 오류 해결 내역을 토대로 Intel 환경용으로 정리했습니다. Intel 서버와 폐쇄망에서 실기 검증을 완료했다는 의미는 아니며, 각 가이드의 인수 절차를 대상 환경에서 수행해야 합니다.

설치 중 확인한 wheel 404, glibc 버전 불일치, C++ 컴파일러 누락 문제와 해결 방법을 포함합니다. GPU 드라이버와 CUDA는 설치하지 않습니다.

폐쇄망 설치는 인터넷 연결 준비 서버와 대상 서버를 구분합니다. 먼저 준비 서버에서 인터넷 연결 가이드의 설치 및 API 검증을 완료한 뒤 폐쇄망 가이드의 반입물 수집 절차를 진행합니다.

작성 기준일: 2026년 11월 11일
