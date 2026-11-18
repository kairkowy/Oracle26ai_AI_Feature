-- Read-only diagnostics from a second SQL session as the same lab user.
SET DEFINE OFF
SET LINESIZE 220
SET PAGESIZE 100
COLUMN job_name FORMAT A35
COLUMN status FORMAT A15

PROMPT Running scheduler jobs for this team (not LLM inference progress)
SELECT job_name, session_id, elapsed_time, cpu_used
FROM user_scheduler_running_jobs
WHERE job_name LIKE 'STD_PRODUCT_TEAM%'
ORDER BY job_name;

PROMPT Recent completed job runs for this team
SELECT log_date, job_name, status, error#, run_duration
FROM user_scheduler_job_run_details
WHERE job_name LIKE 'STD_PRODUCT_TEAM%'
ORDER BY log_date DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT Available Agent history views; inspect their columns before querying
SELECT owner, object_name, object_type
FROM all_objects
WHERE object_name IN ('USER_AI_AGENT_TEAM_HISTORY', 'USER_AI_AGENT_TASK_HISTORY',
                      'USER_AI_AGENT_TOOL_HISTORY', 'USER_CLOUD_AI_CONVERSATION_PROMPTS')
ORDER BY object_name;

-- Optional on releases that provide these views:
-- DESC USER_AI_AGENT_TOOL_HISTORY
-- DESC USER_AI_AGENT_TASK_HISTORY
-- Do not cancel, rerun or delete jobs based only on an empty running-jobs result.
