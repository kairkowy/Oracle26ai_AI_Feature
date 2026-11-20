-- Native RUN_TEAM 호출별 추적 메모리 POC_V2_EXECS를 생성한다.
-- request_id로 업무 요청에 연결하며 Native 대화 ID·단계 전후 상태·Task 이력 스냅샷을 보관한다. 판단의 기준 상태는 RUNS다.

CREATE TABLE POC_V2_EXECS (
 execution_id VARCHAR2(32) CONSTRAINT POC_V2_EXECS_PK PRIMARY KEY,
 request_id VARCHAR2(32) NOT NULL REFERENCES POC_V2_RUNS(request_id),
 revision NUMBER NOT NULL,
 round_no NUMBER NOT NULL,
 conversation_id VARCHAR2(128) NOT NULL,
 state_before VARCHAR2(40),
 state_after VARCHAR2(40),
 steps_before NUMBER,
 steps_after NUMBER,
 native_state VARCHAR2(40),
 raw_output CLOB,
 error_message VARCHAR2(2000),
 task_history_json CLOB,
 started_at TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
 ended_at TIMESTAMP WITH TIME ZONE,
 CONSTRAINT POC_V2_EXECS_ROUND_UQ UNIQUE(request_id,round_no),
 CONSTRAINT POC_V2_EXECS_HIST_CK CHECK(task_history_json IS JSON)
);
