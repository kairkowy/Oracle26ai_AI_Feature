-- Read-only. Same lab user, separate session. Does not call the LLM.
SET DEFINE OFF
SET LONG 10000
SET LINESIZE 220
SET PAGESIZE 100

SELECT team_exec_id, task_order, task_name, state, start_date, end_date,
       DBMS_LOB.SUBSTR(result, 1500, 1) AS result
FROM user_ai_agent_task_history
WHERE team_exec_id = (
  SELECT team_exec_id FROM user_ai_agent_task_history
  WHERE team_name = 'STD_PRODUCT_TEAM' AND start_date IS NOT NULL
  ORDER BY start_date DESC
  FETCH FIRST 1 ROW ONLY
)
ORDER BY task_order;

SELECT invocation_id, team_exec_id, task_order, tool_name, start_date, end_date,
       DBMS_LOB.SUBSTR(input, 1500, 1) AS tool_input,
       DBMS_LOB.SUBSTR(output, 2500, 1) AS output
FROM user_ai_agent_tool_history
WHERE team_exec_id = (
  SELECT team_exec_id FROM user_ai_agent_task_history
  WHERE team_name = 'STD_PRODUCT_TEAM' AND start_date IS NOT NULL
  ORDER BY start_date DESC
  FETCH FIRST 1 ROW ONLY
)
ORDER BY invocation_id;

-- Success requires both tasks to have completion dates, lookup before SQL,
-- real product ID 41 passed to SQL, and generated SQL restricting PROD_ID to 41.
-- This test requests SQL generation only, not execution or a fabricated result.
-- If the Agent loops again, do not launch another run.
-- DBA: identify the CURRENT full-test session before considering cancellation:
-- SELECT inst_id, sid, serial#, username, sql_id, event, state
-- FROM gv$session WHERE client_identifier = 'STD_FULL_PRODUCT_TEST';
-- Inspect that session's current SQL, then cancel only that statement if needed:
-- ALTER SYSTEM CANCEL SQL 'SID,SERIAL#,@INST_ID,SQL_ID';
