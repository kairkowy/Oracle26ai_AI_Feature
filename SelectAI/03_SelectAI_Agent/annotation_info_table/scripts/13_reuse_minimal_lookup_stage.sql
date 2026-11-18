-- Controlled comparison after cancelling the looping full-team call.
-- First rerun 09_run_minimal_agent.sql once and confirm it returns successfully.
-- Reuse those CURRENT lookup Agent/Task objects as stage 0 of the full team.
-- Does not change the model, profile, data, function, lookup Task or lookup Agent.
SET DEFINE OFF
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

BEGIN
  DBMS_CLOUD_AI_AGENT.SET_ATTRIBUTE(
    object_name => 'STD_PRODUCT_SQL_TASK',
    object_type => 'task',
    attribute_name => 'input',
    attribute_value => 'STD_MIN_LOOKUP_TASK'
  );

  DBMS_CLOUD_AI_AGENT.SET_ATTRIBUTE(
    object_name => 'STD_PRODUCT_SQL_TASK',
    object_type => 'task',
    attribute_name => 'instruction',
    attribute_value => 'Original question: {query}. The preceding product lookup task reports actual lookup results in natural language or JSON. Read the returned product ID without requiring a particular JSON schema. If lookup reports no match, invalid input or unresolved multiple candidates, return that issue and finish without calling a tool. Otherwise call STD_PRODUCT_SQL once using showsql, the original requested fields and conditions, and an explicit PRODUCTS.PROD_ID restriction using the returned ID. Do not translate the Korean expression into an English name condition. After the SQL tool returns, finish with the ID and generated SQL unchanged. State that SQL was not executed. If the SQL lacks the verified ID restriction, report validation failure and finish. Do not retry indefinitely or add currency assumptions.'
  );

  DBMS_CLOUD_AI_AGENT.SET_ATTRIBUTE(
    object_name => 'STD_PRODUCT_TEAM',
    object_type => 'team',
    attribute_name => 'agents',
    attribute_value => '[{"name":"STD_MIN_LOOKUP_AGENT","task":"STD_MIN_LOOKUP_TASK"},{"name":"STD_PRODUCT_AGENT","task":"STD_PRODUCT_SQL_TASK"}]'
  );
END;
/
PROMPT Full team now uses the minimal lookup Agent/Task as stage 0.
PROMPT Run 04_run_agent.sql once, and inspect with 12_inspect_full_agent.sql.
-- Hypothesis test only: this does not guarantee multi-task completion.
-- Do not rerun 11_update_full_agent.sql during this comparison; it changes task text.
