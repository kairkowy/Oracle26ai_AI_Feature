-- Update existing objects only. No table/profile/Agent recreation.
-- Use after a minimal lookup run has returned and ended successfully.
SET DEFINE OFF
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

BEGIN
  DBMS_CLOUD_AI_AGENT.SET_ATTRIBUTE(
    object_name => 'STD_PRODUCT_AGENT',
    object_type => 'agent',
    attribute_name => 'role',
    attribute_value => 'Complete only the current task using its available tools. Use actual tool results as evidence. Never invent product mappings, query results or currency units. Respond in Korean and follow the framework-required final response format.'
  );

  DBMS_CLOUD_AI_AGENT.SET_ATTRIBUTE(
    object_name => 'STD_RESOLVE_PRODUCT_TASK',
    object_type => 'task',
    attribute_name => 'instruction',
    attribute_value => 'Question: {query}. Your only job is product resolution. Extract each original product expression without translating it. Call STD_SEARCH_PRODUCT once per distinct expression. The result field can contain a JSON string; read that string as JSON. After all tool results return, this task is complete. Immediately return a final task result containing the original question, each expression, lookup status and deduplicated product IDs. MATCH, NOT_FOUND, AMBIGUOUS and INVALID_INPUT are all terminal outcomes. Include candidates for AMBIGUOUS and finish without choosing one. Do not retry the same expression, generate SQL, or wait for the next task. Do not add a currency unit absent from the tool result.'
  );

  DBMS_CLOUD_AI_AGENT.SET_ATTRIBUTE(
    object_name => 'STD_PRODUCT_SQL',
    object_type => 'tool',
    attribute_name => 'instruction',
    attribute_value => 'Generate SQL using showsql only for this diagnostic test; do not use runsql. Use only the product IDs verified in the preceding resolution result. Do not translate Korean names into English name filters. Preserve the requested output fields, numeric and date conditions. Revenue is SUM(SALES.AMOUNT_SOLD). Join SALES.PROD_ID to PRODUCTS.PROD_ID and SALES.TIME_ID to TIMES.TIME_ID; calendar year is TIMES.CALENDAR_YEAR. Deduplicate product IDs. Return the generated SQL unchanged; do not claim it was executed or add currency assumptions.'
  );

  DBMS_CLOUD_AI_AGENT.SET_ATTRIBUTE(
    object_name => 'STD_PRODUCT_SQL_TASK',
    object_type => 'task',
    attribute_name => 'instruction',
    attribute_value => 'Original question: {query}. Read the preceding resolution task. If any expression has no MATCH, finish with the lookup status or a candidate clarification question and do not call STD_PRODUCT_SQL. Otherwise call STD_PRODUCT_SQL once, requesting showsql only. Include the original requested output and filters and an explicit PRODUCTS.PROD_ID restriction using the verified deduplicated IDs. Do not pass the Korean expression as a product-name filter. After the SQL tool returns, finish this task with the resolved IDs and generated SQL. State that SQL was generated and was not executed. If the SQL ignores the verified IDs, report that validation failed rather than retrying indefinitely. Do not add currency units or fabricate query results.'
  );

  DBMS_CLOUD_AI_AGENT.SET_ATTRIBUTE(
    object_name => 'STD_MIN_LOOKUP_TASK',
    object_type => 'task',
    attribute_name => 'instruction',
    attribute_value => 'Question: {query}. Extract the original product expression without translating it. Call STD_SEARCH_PRODUCT once with that expression. Once the tool returns, finish this task with a final response in the format required by the framework. Report the returned status, product ID, original English product name and numeric price in Korean. Do not add a currency unit unless it is explicitly returned by the tool. For multiple matches list the candidates; for no match report no match. Every returned status completes this task. Do not call the tool again, generate SQL, wait for another task or invent observations.'
  );
END;
/
PROMPT Full Agent instructions updated. Run 04_run_agent.sql once.
-- These are LLM instructions, not a database execution-permission restriction.
