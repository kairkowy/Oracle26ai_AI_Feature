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
