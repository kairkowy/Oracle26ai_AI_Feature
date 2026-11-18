-- Use after identifying a reachable base endpoint and an installed model.
-- Changes only the existing profile; no Agent/team/table recreation required.
SET DEFINE ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
ACCEPT FIX_AGENT_ENDPOINT CHAR PROMPT 'Verified provider_endpoint (example http://service-ollama/v1): '
ACCEPT FIX_AGENT_MODEL CHAR PROMPT 'Exact installed model ID from /v1/models: '
BEGIN
  DBMS_CLOUD_AI.SET_ATTRIBUTE(
    profile_name => 'STD_PRODUCT_AGENT_PROFILE',
    attribute_name => 'provider_endpoint',
    attribute_value => '&&FIX_AGENT_ENDPOINT'
  );
  DBMS_CLOUD_AI.SET_ATTRIBUTE(
    profile_name => 'STD_PRODUCT_AGENT_PROFILE',
    attribute_name => 'model',
    attribute_value => '&&FIX_AGENT_MODEL'
  );
END;
/
UNDEFINE FIX_AGENT_ENDPOINT
UNDEFINE FIX_AGENT_MODEL
SET DEFINE OFF
SET LONG 100000
PROMPT Test a simple chat first. If it succeeds, retry 04_run_agent.sql.
SELECT DBMS_CLOUD_AI.GENERATE(
  prompt => 'Reply OK.',
  profile_name => 'STD_PRODUCT_AGENT_PROFILE',
  action => 'chat'
) AS connection_test FROM dual;
