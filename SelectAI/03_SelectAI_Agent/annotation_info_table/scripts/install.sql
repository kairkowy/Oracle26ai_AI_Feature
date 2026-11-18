-- Run from SQLcl/SQL*Plus: @install.sql
-- Check AGENT_ENDPOINT in 02_create_agent.sql; enter the installed model when prompted.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
@@00_precheck.sql
@@01_create_search_function.sql
@@03_verify_lookup.sql
@@02_create_agent.sql
PROMPT Installation complete. Run 04_run_agent.sql to make a live LLM request.
