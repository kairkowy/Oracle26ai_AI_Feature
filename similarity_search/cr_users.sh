#!/bin/bash

# dev 그룹 존재 여부 확인 후 없으면 생성
if ! getent group dev > /dev/null; then
    echo "그룹 dev 생성"
    groupadd dev
fi

# lab01 ~ lab25 생성
for i in $(seq -w 1 25); do
    USER="lab$i"
    echo "==> 생성 중: $USER"

    # 사용자 추가 (홈디렉토리 생성, 기본 쉘 bash)
    useradd -m -s /bin/bash -g dev "$USER"

    # 비밀번호를 사용자명과 동일하게 설정 (ex. lab01 → lab01)
    echo "$USER:$USER" | chpasswd

done

echo "모든 계정 생성 완료!"
