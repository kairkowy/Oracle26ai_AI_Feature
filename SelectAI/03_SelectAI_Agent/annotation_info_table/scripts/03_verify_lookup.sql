-- Tests the real lookup function without any LLM/Agent API calls.
SET DEFINE OFF
SET SERVEROUTPUT ON
SET LONG 100000
SET LONGCHUNKSIZE 100000
SET SQLBLANKLINES ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

DECLARE
  l_json JSON_OBJECT_T;
  l_matches JSON_ARRAY_T;
  l_item JSON_OBJECT_T;
  PROCEDURE assert_match(p_term VARCHAR2, p_id NUMBER) IS
  BEGIN
    l_json := JSON_OBJECT_T.parse(std_agent_find_product(p_term));
    IF l_json.get_string('status') <> 'MATCH' THEN
      RAISE_APPLICATION_ERROR(-20110, 'Expected MATCH for: ' || p_term);
    END IF;
    l_matches := l_json.get_array('matches');
    l_item := TREAT(l_matches.get(0) AS JSON_OBJECT_T);
    IF l_item.get_number('prod_id') <> p_id THEN
      RAISE_APPLICATION_ERROR(-20111, 'Unexpected product ID for: ' || p_term);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PASS: ' || p_term || ' -> ' || p_id);
  END;
BEGIN
  assert_match('남아공 크리켓 팀 유니폼', 41);
  assert_match('프로 메이플 배트', 129);
  assert_match('프로 단풍나무 야구방망이', 129);
  assert_match('프로 주니어 단풍나무 야구방망이', 130);
  assert_match('pro maple bat', 129);
  assert_match(' PRO MAPLE YOUTH BAT ', 130);
  assert_match('프로메이플배트', 129);

  l_json := JSON_OBJECT_T.parse(std_agent_find_product('존재하지않는테스트상품XYZ'));
  IF l_json.get_string('status') <> 'NOT_FOUND' THEN
    RAISE_APPLICATION_ERROR(-20112, 'Unknown term should not resolve.');
  END IF;
  l_json := JSON_OBJECT_T.parse(std_agent_find_product('Team shirt'));
  IF l_json.get_string('status') <> 'AMBIGUOUS'
     OR l_json.get_number('match_count') <> 6 THEN
    RAISE_APPLICATION_ERROR(-20113, 'Team shirt must have six candidates for the original sample.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: missing and ambiguous terms are not silently mapped.');
END;
/

SELECT std_agent_find_product('남아공 크리켓 팀 유니폼') AS actual_lookup FROM dual;

-- Optional on releases with RUN_TOOL: verifies registered tool dispatch without LLM reasoning.
-- SELECT DBMS_CLOUD_AI_AGENT.RUN_TOOL(
--   tool_name => 'STD_SEARCH_PRODUCT',
--   input => '{"P_TERM":"남아공 크리켓 팀 유니폼"}'
-- ) AS tool_result FROM dual;
