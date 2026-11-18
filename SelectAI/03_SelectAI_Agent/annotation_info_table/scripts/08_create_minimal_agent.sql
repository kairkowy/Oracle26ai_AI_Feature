-- Diagnostic control: one Agent, one Task, one existing lookup Tool.
-- Reuse the same function/tool/profile/model to isolate task completion behavior.
-- No original objects are changed. No SQL generation tool is attached.
SET DEFINE OFF
SET SERVEROUTPUT ON
SET SQLBLANKLINES ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM user_cloud_ai_profiles
  WHERE profile_name = 'STD_PRODUCT_AGENT_PROFILE';
  IF l_count <> 1 THEN
    RAISE_APPLICATION_ERROR(-20130, 'Create STD_PRODUCT_AGENT_PROFILE first.');
  END IF;
END;
/

-- Direct function output is a baseline, not an Agent call.
SET LONG 10000
SELECT std_agent_find_product('남아공 크리켓 팀 유니폼') AS direct_lookup FROM dual;

BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'STD_MIN_LOOKUP_AGENT',
    attributes => '{
      "profile_name":"STD_PRODUCT_AGENT_PROFILE",
      "role":"You look up a product using the available tool and report its result. Complete only the current lookup task.",
      "enable_human_tool":false
    }'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name => 'STD_MIN_LOOKUP_TASK',
    attributes => '{
      "instruction":"Question: {query}. Extract the original product expression without translating it. Call STD_SEARCH_PRODUCT once with that expression. Once the tool returns, finish this task with a final response in the format required by the framework. Report the returned status, product ID, original English product name and price in Korean. For multiple matches list the candidates; for no match report no match. Every returned status completes this lookup task. Do not call the tool again, do not generate SQL, and do not wait for another task. Do not invent tool observations or product data.",
      "tools":["STD_SEARCH_PRODUCT"],
      "enable_human_tool":false
    }'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name => 'STD_MIN_LOOKUP_TEAM',
    attributes => '{
      "agents":[{"name":"STD_MIN_LOOKUP_AGENT","task":"STD_MIN_LOOKUP_TASK"}],
      "process":"sequential"
    }'
  );
END;
/
PROMPT Created STD_MIN_LOOKUP_TEAM. Run 09_run_minimal_agent.sql once.
