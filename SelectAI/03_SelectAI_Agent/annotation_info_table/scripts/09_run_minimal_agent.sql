-- Start only after the prior looping call is cancelled and Ollama logs have stopped.
-- This makes one team request, not a retry loop. The Agent may still loop internally.
-- There is no automatic timeout/cancellation configured by this script.
SET DEFINE OFF
SET SERVEROUTPUT ON
SET LONG 100000
SET LONGCHUNKSIZE 10000
SET LINESIZE 200
SET SQLBLANKLINES ON

SELECT SYSTIMESTAMP AS test_started FROM dual;
-- Display the actual current model; do not change models during this control test.
SELECT attribute_name, attribute_value
FROM user_cloud_ai_profile_attributes
WHERE profile_name = 'STD_PRODUCT_AGENT_PROFILE'
AND LOWER(attribute_name) IN ('model','provider_endpoint');

VARIABLE minimal_response CLOB
DECLARE
  l_previous_identifier VARCHAR2(64) := SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER');
BEGIN
  DBMS_SESSION.SET_IDENTIFIER('STD_MIN_LOOKUP_TEST');
  BEGIN
    :minimal_response := DBMS_CLOUD_AI_AGENT.RUN_TEAM(
      team_name => 'STD_MIN_LOOKUP_TEAM',
      user_prompt => '남아공 크리켓 팀 유니폼의 상품 ID와 영문 상품명과 정가를 보여줘.'
    );
  EXCEPTION
    WHEN OTHERS THEN
      IF l_previous_identifier IS NULL THEN
        DBMS_SESSION.CLEAR_IDENTIFIER;
      ELSE
        DBMS_SESSION.SET_IDENTIFIER(l_previous_identifier);
      END IF;
      RAISE;
  END;
  IF l_previous_identifier IS NULL THEN
    DBMS_SESSION.CLEAR_IDENTIFIER;
  ELSE
    DBMS_SESSION.SET_IDENTIFIER(l_previous_identifier);
  END IF;
END;
/
PRINT minimal_response
PROMPT Inspect the run with 10_inspect_minimal_agent.sql from another session if needed.
