-- 클라이언트 취소 이후 늦게 도착하는 Worker 호출을 차단하는 요청 폐기 함수.
-- 이 함수는 요청 상태/토큰만 무효화한다. 실행 중 DB 호출 중단은 드라이버 break()가 담당하며 Oracle 내부 이력은 수정하지 않는다.

-- 클라이언트의 break()/callTimeout 이후 늦은 Tool 호출을 막는 요청 폐기 함수.
-- Oracle 내부 Task 이력은 수정하지 않는다. 실행 중 SQL 취소 자체는 클라이언트 드라이버가 담당한다.
CREATE OR REPLACE FUNCTION POC_V2_CANCEL_FN(p_request_id VARCHAR2,p_revision NUMBER) RETURN CLOB AUTHID CURRENT_USER IS
 PRAGMA AUTONOMOUS_TRANSACTION;r POC_V2_RUNS%ROWTYPE;o JSON_OBJECT_T:=JSON_OBJECT_T();
BEGIN
 SELECT * INTO r FROM POC_V2_RUNS WHERE request_id=p_request_id FOR UPDATE NOWAIT;
 IF r.revision<>p_revision THEN RAISE_APPLICATION_ERROR(-20402,'STALE_REVISION');END IF;
 IF r.state<>'SUCCEEDED' THEN
  UPDATE POC_V2_RUNS SET state='FAILED',runner_active='N',runner_token=NULL,last_error='CLIENT_CANCELLED',updated_at=SYSTIMESTAMP WHERE request_id=p_request_id;
 END IF;
 o.put('request_id',p_request_id);o.put('status',CASE WHEN r.state='SUCCEEDED' THEN 'already_completed' ELSE 'cancelled' END);COMMIT;RETURN o.to_clob();
EXCEPTION WHEN OTHERS THEN ROLLBACK;RAISE;END;
/
