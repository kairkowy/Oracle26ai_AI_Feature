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

DECLARE
  l_previous_identifier VARCHAR2(64) := SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER');
  l_previous_conversation VARCHAR2(128) := DBMS_CLOUD_AI.GET_CONVERSATION_ID();
  l_conversation_id VARCHAR2(128);
  l_params JSON_OBJECT_T := JSON_OBJECT_T();
  l_response CLOB;
  l_piece VARCHAR2(32767);
  l_pos PLS_INTEGER := 1;

  PROCEDURE restore_context IS
  BEGIN
    IF l_previous_identifier IS NULL THEN
      DBMS_SESSION.CLEAR_IDENTIFIER;
    ELSE
      DBMS_SESSION.SET_IDENTIFIER(l_previous_identifier);
    END IF;
    IF l_previous_conversation IS NULL THEN
      DBMS_CLOUD_AI.CLEAR_CONVERSATION_ID;
    ELSE
      DBMS_CLOUD_AI.SET_CONVERSATION_ID(l_previous_conversation);
    END IF;
  END;
BEGIN
  DBMS_SESSION.SET_IDENTIFIER('STD_MIN_LOOKUP_TEST');
  BEGIN
    -- Create an actual conversation; SYS_GUID alone would not create its DB row.
    -- Explicit title/description avoid LLM calls to generate conversation metadata.
    l_conversation_id := DBMS_CLOUD_AI.CREATE_CONVERSATION(
      attributes => '{"title":"Minimal product lookup test","description":"Single-task product lookup completion diagnosis","conversation_length":10}'
    );
    IF l_conversation_id IS NULL THEN
      RAISE_APPLICATION_ERROR(-20131, 'CREATE_CONVERSATION returned NULL.');
    END IF;
    DBMS_CLOUD_AI.SET_CONVERSATION_ID(l_conversation_id);
    l_params.put('conversation_id', l_conversation_id);
    DBMS_OUTPUT.PUT_LINE('CONVERSATION_ID=' || l_conversation_id);

    l_response := DBMS_CLOUD_AI_AGENT.RUN_TEAM(
      team_name => 'STD_MIN_LOOKUP_TEAM',
      user_prompt => '남아공 크리켓 팀 유니폼의 상품 ID와 영문 상품명과 정가를 보여줘.',
      params => l_params.to_clob()
    );

    -- Print only a successfully returned response, never an unassigned bind LOB.
    IF l_response IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('RUN_TEAM returned NULL; inspect task history.');
    ELSE
      WHILE l_pos <= DBMS_LOB.GETLENGTH(l_response) LOOP
        l_piece := DBMS_LOB.SUBSTR(l_response, 8000, l_pos);
        DBMS_OUTPUT.PUT_LINE(l_piece);
        l_pos := l_pos + LENGTH(l_piece);
      END LOOP;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      restore_context;
      RAISE;
  END;
  restore_context;
END;
/
-- On error there is no unconditional PRINT and no success message.
-- Inspect with 10_inspect_minimal_agent.sql from another session if needed.
