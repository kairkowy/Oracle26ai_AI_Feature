SET DEFINE OFF
SET LONG 1000000
SET LONGCHUNKSIZE 100000
SET LINESIZE 200
SET PAGESIZE 100
SET SQLBLANKLINES ON

-- One live Agent run. Default task policy is SQL generation, not query execution.
SELECT DBMS_CLOUD_AI_AGENT.RUN_TEAM(
  team_name => 'STD_PRODUCT_TEAM',
  user_prompt => '남아공 크리켓 팀 유니폼의 상품 ID와 영문 상품명과 정가를 조회하는 SQL을 만들어줘. 실행하지 말고 SQL을 보여줘.'
) AS response FROM dual;

-- Expected evidence: STD_SEARCH_PRODUCT called with the original Korean term,
-- actual lookup returns PROD_ID=41, then SQL constrains PRODUCTS.PROD_ID=41.
-- An English LIKE filter such as SOUTH AFRICA CRICKET TEAM is a failed test.

-- Further runs (uncomment one at a time):
-- SELECT DBMS_CLOUD_AI_AGENT.RUN_TEAM(
--   team_name => 'STD_PRODUCT_TEAM',
--   user_prompt => '프로 메이플 배트 또는 프로 단풍나무 야구방망이의 연도별 매출액을 조회하는 SQL을 만들어줘. 실행하지 마.'
-- ) AS response FROM dual;
-- Expected: a deduplicated product restriction on 129, calendar_year and SUM(amount_sold).

-- SELECT DBMS_CLOUD_AI_AGENT.RUN_TEAM(
--   team_name => 'STD_PRODUCT_TEAM',
--   user_prompt => '존재하지않는테스트상품XYZ의 정가 조회 SQL을 만들어줘.'
-- ) AS response FROM dual;
-- Expected: lookup NOT_FOUND, no SQL tool call.

-- SELECT DBMS_CLOUD_AI_AGENT.RUN_TEAM(
--   team_name => 'STD_PRODUCT_TEAM',
--   user_prompt => 'Team shirt의 정가 조회 SQL을 만들어줘.'
-- ) AS response FROM dual;
-- Expected: six candidates and a clarification request, no SQL tool call.

-- Alternative interactive SQL interface (syntax depends on the installed release):
-- EXEC DBMS_CLOUD_AI_AGENT.SET_TEAM('STD_PRODUCT_TEAM');
-- SELECT AI agent 남아공 크리켓 팀 유니폼의 정가를 조회하는 SQL을 만들어줘;
-- EXEC DBMS_CLOUD_AI_AGENT.CLEAR_TEAM;
-- CLEAR_TEAM is necessary before returning to ordinary SELECT AI showsql/runsql.

-- Optional newer release history views: check 00_precheck.sql before querying.
-- DESC USER_AI_AGENT_TOOL_HISTORY
-- SELECT * FROM user_ai_agent_tool_history FETCH FIRST 20 ROWS ONLY;
-- DESC USER_AI_AGENT_TASK_HISTORY
-- SELECT * FROM user_ai_agent_task_history FETCH FIRST 20 ROWS ONLY;
