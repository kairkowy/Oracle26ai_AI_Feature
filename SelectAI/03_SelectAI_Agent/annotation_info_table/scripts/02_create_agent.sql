-- First installation only: these dedicated profile/tool/task/agent/team names must be new.
-- Does not change existing annotations, views, dictionary data or lab profiles.
SET DEFINE ON
SET VERIFY OFF
SET SQLBLANKLINES ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DEFINE AGENT_ENDPOINT = http://service-ollama/v1
-- An absent model can produce HTTP 404 even when the endpoint path is correct.
-- Enter the exact model ID returned by this endpoint's GET /v1/models.
ACCEPT AGENT_MODEL CHAR PROMPT 'Installed model ID from /v1/models: '
COLUMN std_agent_owner NEW_VALUE STD_AGENT_OWNER NOPRINT
SELECT USER AS std_agent_owner FROM dual;

BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'STD_PRODUCT_AGENT_PROFILE',
    attributes => '{
      "provider_endpoint": "&&AGENT_ENDPOINT",
      "model": "&&AGENT_MODEL",
      "object_list": [
        {"owner":"&&STD_AGENT_OWNER", "name":"PRODUCTS"},
        {"owner":"&&STD_AGENT_OWNER", "name":"SALES"},
        {"owner":"&&STD_AGENT_OWNER", "name":"TIMES"}
      ],
      "annotations": false,
      "comments": false,
      "constraints": true,
      "enforce_object_list": true,
      "conversation": false,
      "temperature": 0,
      "max_tokens": 4096
    }',
    description => 'Agent lookup followed by NL2SQL using resolved product IDs'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'STD_SEARCH_PRODUCT',
    attributes => '{
      "function":"STD_AGENT_FIND_PRODUCT",
      "instruction":"Look up an actual product in PRODUCTS and DATA_STANDARD. p_term is the original Korean or English product expression extracted from the question, without grammatical particles or requested output fields. Never translate it first. Returns MATCH, AMBIGUOUS, NOT_FOUND or INVALID_INPUT and actual product IDs.",
      "tool_inputs":[{"name":"P_TERM","description":"Original product expression only, without translation. For several expressions call this tool separately for each one."}]
    }'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name => 'STD_PRODUCT_SQL',
    attributes => '{
      "tool_type":"SQL",
      "tool_params":{"profile_name":"STD_PRODUCT_AGENT_PROFILE"},
      "instruction":"Generate SQL using showsql only for this diagnostic test; do not use runsql. Use only the product IDs verified in the preceding resolution result. Do not translate Korean names into English name filters. Preserve the requested output fields, numeric and date conditions. Revenue is SUM(SALES.AMOUNT_SOLD). Join SALES.PROD_ID to PRODUCTS.PROD_ID and SALES.TIME_ID to TIMES.TIME_ID; calendar year is TIMES.CALENDAR_YEAR. Deduplicate product IDs. Return the generated SQL unchanged; do not claim it was executed or add currency assumptions."
    }'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name => 'STD_PRODUCT_AGENT',
    attributes => '{
      "profile_name":"STD_PRODUCT_AGENT_PROFILE",
      "role":"Complete only the current task using its available tools. Use actual tool results as evidence. Never invent product mappings, query results or currency units. Respond in Korean and follow the framework-required final response format.",
      "enable_human_tool":false
    }'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name => 'STD_RESOLVE_PRODUCT_TASK',
    attributes => '{
      "instruction":"Question: {query}. Your only job is product resolution. Extract each original product expression without translating it. Call STD_SEARCH_PRODUCT once per distinct expression. The result field can contain a JSON string; read that string as JSON. After all tool results return, this task is complete. Immediately return a final task result containing the original question, each expression, lookup status and deduplicated product IDs. MATCH, NOT_FOUND, AMBIGUOUS and INVALID_INPUT are all terminal outcomes. Include candidates for AMBIGUOUS and finish without choosing one. Do not retry the same expression, generate SQL, or wait for the next task. Do not add a currency unit absent from the tool result.",
      "tools":["STD_SEARCH_PRODUCT"],
      "enable_human_tool":false
    }'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name => 'STD_PRODUCT_SQL_TASK',
    attributes => '{
      "input":"STD_RESOLVE_PRODUCT_TASK",
      "instruction":"Original question: {query}. Read the preceding resolution task. If any expression has no MATCH, finish with the lookup status or a candidate clarification question and do not call STD_PRODUCT_SQL. Otherwise call STD_PRODUCT_SQL once, requesting showsql only. Include the original requested output and filters and an explicit PRODUCTS.PROD_ID restriction using the verified deduplicated IDs. Do not pass the Korean expression as a product-name filter. After the SQL tool returns, finish this task with the resolved IDs and generated SQL. State that SQL was generated and was not executed. If the SQL ignores the verified IDs, report that validation failed rather than retrying indefinitely. Do not add currency units or fabricate query results.",
      "tools":["STD_PRODUCT_SQL"],
      "enable_human_tool":false
    }'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name => 'STD_PRODUCT_TEAM',
    attributes => '{
      "agents":[
        {"name":"STD_PRODUCT_AGENT","task":"STD_RESOLVE_PRODUCT_TASK"},
        {"name":"STD_PRODUCT_AGENT","task":"STD_PRODUCT_SQL_TASK"}
      ],
      "process":"sequential"
    }'
  );
END;
/
SET DEFINE OFF
PROMPT Agent created. Run 03_verify_lookup.sql before calling the LLM.
