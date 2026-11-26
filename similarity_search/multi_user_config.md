# 여러 사용자 실습 계정 준비와 정리

Linux OS 계정과 Oracle DB 계정은 별개입니다. OS 예제는 `lab01`~`lab25`, DB 정리 예제는 `USER_01`~`USER_NN`을 사용합니다. 실제 실습에서 사용할 이름을 맞춰 적용합니다.

## Linux OS 계정 생성

Linux 관리자 권한으로 실행하는 예제입니다. 원본의 초기 비밀번호는 사용자명과 같으므로 실제 운영 정책에 맞게 변경합니다. 실행 파일은 [cr_users.sh](cr_users.sh)입니다.

```bash
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
```

## Oracle DB 계정 정리 SQL

관리자로 대상 PDB에 접속한 뒤 SQL*Plus·SQLcl에서 실행합니다. 기본값은 삭제 대상만 출력합니다. `DO_DELETE`를 `YES`로 수정하면 해당 계정과 소유 객체를 삭제합니다. 원본 메모가 참조한 계정 생성 SQL은 제공되지 않아 생성 구문은 포함하지 않았습니다.

```sql
-- 여러 실습 계정 정리용 참고 스크립트 (관리자 / 대상 PDB).
-- 원본 메모의 create_users.sql은 제공되지 않아 계정 생성은 포함하지 않습니다.
-- USER_01 ~ USER_NN의 모든 객체를 삭제하므로 대상 계정을 먼저 확인합니다.
-- 실행 전 DO_DELETE 값을 YES로 바꾸어야 삭제를 수행합니다.
SET SERVEROUTPUT ON
DEFINE DO_DELETE = NO
ACCEPT LAB_USER_COUNT NUMBER PROMPT '정리할 USER_ 계정 수: '

DECLARE
    v_count PLS_INTEGER := &LAB_USER_COUNT;
    v_username VARCHAR2(30);
BEGIN
    IF v_count < 1 OR v_count > 99 THEN
        RAISE_APPLICATION_ERROR(-20001, '계정 수는 1~99 범위로 입력하세요.');
    END IF;
    FOR i IN 1 .. v_count LOOP
        v_username := 'USER_' || TO_CHAR(i, 'FM00');
        IF UPPER('&DO_DELETE') = 'YES' THEN
            EXECUTE IMMEDIATE 'DROP USER ' || v_username || ' CASCADE';
            DBMS_OUTPUT.PUT_LINE('Dropped user ' || v_username);
        ELSE
            DBMS_OUTPUT.PUT_LINE('대상 확인 (삭제하지 않음): ' || v_username);
        END IF;
    END LOOP;
END;
/
UNDEFINE LAB_USER_COUNT
UNDEFINE DO_DELETE
```

[공통 환경 준비](00.Setup.md) · [전체 실습 안내](readme.md)
