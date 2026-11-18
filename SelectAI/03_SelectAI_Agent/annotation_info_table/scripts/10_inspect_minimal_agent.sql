-- Same lab user, separate session. Read-only checks; this does not call the LLM.
SET DEFINE OFF
SET LONG 10000
SET LINESIZE 220
SET PAGESIZE 100

SELECT team_exec_id, task_order, task_name, state, start_date, end_date,
       DBMS_LOB.SUBSTR(result, 1500, 1) AS result
FROM user_ai_agent_task_history
WHERE team_name = 'STD_MIN_LOOKUP_TEAM'
ORDER BY start_date DESC NULLS LAST
FETCH FIRST 5 ROWS ONLY;

SELECT invocation_id, team_exec_id, tool_name, start_date, end_date,
       DBMS_LOB.SUBSTR(input, 1000, 1) AS tool_input,
       DBMS_LOB.SUBSTR(output, 2000, 1) AS output
FROM user_ai_agent_tool_history
WHERE team_exec_id = (
  SELECT team_exec_id FROM user_ai_agent_task_history
  WHERE team_name = 'STD_MIN_LOOKUP_TEAM' AND start_date IS NOT NULL
  ORDER BY start_date DESC
  FETCH FIRST 1 ROW ONLY
)
ORDER BY invocation_id DESC
FETCH FIRST 5 ROWS ONLY;

-- DBA-only checks below are commented out. Run in the same PDB as the lab.
-- The marker identifies THIS minimal test, not a historical SID from another run.
-- SELECT inst_id, sid, serial#, username, status, sql_id, event, state,
--        client_identifier
-- FROM gv$session
-- WHERE client_identifier = 'STD_MIN_LOOKUP_TEST';
--
-- To prepare cancellation, inspect the current statement first:
-- SELECT s.inst_id, s.sid, s.serial#, s.sql_id, q.sql_fulltext
-- FROM gv$session s
-- LEFT JOIN gv$sql q ON q.inst_id = s.inst_id AND q.sql_id = s.sql_id
--                  AND q.child_number = s.sql_child_number
-- WHERE s.client_identifier = 'STD_MIN_LOOKUP_TEST';
--
-- If rapid repetitive requests persist after one successful lookup, cancel ONLY
-- the identified test SQL using its CURRENT values (not a previous test's SID):
-- ALTER SYSTEM CANCEL SQL 'SID,SERIAL#,@INST_ID,SQL_ID';
-- Do not update task history to force its state to completed.
