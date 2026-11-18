-- Run in SQLcl/SQL*Plus as the existing lab owner (for example LAB).
SET DEFINE OFF
SET SERVEROUTPUT ON
SET SQLBLANKLINES ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

SELECT USER AS lab_owner, SYS_CONTEXT('USERENV','CON_NAME') AS pdb FROM dual;
SELECT banner_full FROM v$version;

-- Verify the actual installed API, not just the marketing version '26ai'.
SELECT owner, object_name, procedure_name
FROM all_procedures
WHERE object_name = 'DBMS_CLOUD_AI_AGENT'
AND procedure_name IN (
  'CREATE_AGENT', 'CREATE_TOOL', 'CREATE_TASK', 'CREATE_TEAM',
  'RUN_TEAM', 'SET_TEAM', 'CLEAR_TEAM'
)
ORDER BY owner, procedure_name;

DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(DISTINCT procedure_name) INTO l_count
  FROM all_procedures
  WHERE object_name = 'DBMS_CLOUD_AI_AGENT'
  AND procedure_name IN ('CREATE_AGENT','CREATE_TOOL','CREATE_TASK',
                        'CREATE_TEAM','RUN_TEAM','SET_TEAM','CLEAR_TEAM');
  IF l_count < 7 THEN
    RAISE_APPLICATION_ERROR(-20100,
      'Required DBMS_CLOUD_AI_AGENT APIs are unavailable. Check installed RU/package and EXECUTE grants.');
  END IF;
  SELECT COUNT(*) INTO l_count FROM data_standard;
  IF l_count = 0 THEN
    RAISE_APPLICATION_ERROR(-20101, 'Populate DATA_STANDARD before creating this agent.');
  END IF;
  SELECT COUNT(*) INTO l_count FROM data_standard d
  JOIN products p ON p.prod_id = d.prod_id
  WHERE d.term_ko = '남아공 크리켓 팀 유니폼' AND p.prod_id = 41;
  IF l_count <> 1 THEN
    RAISE_APPLICATION_ERROR(-20102, 'Expected lab alias for product 41 was not found.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PASS: required APIs and sample dictionary row are visible.');
END;
/

-- Optional newer history views: query only those actually installed.
SELECT owner, object_name, object_type
FROM all_objects
WHERE object_name IN ('USER_AI_AGENT_TEAM_HISTORY', 'USER_AI_AGENT_TASK_HISTORY',
                      'USER_AI_AGENT_TOOL_HISTORY', 'USER_CLOUD_AI_CONVERSATION_PROMPTS')
ORDER BY object_name;

-- DBA prerequisite if needed, connected to the same PDB:
-- GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO LAB;
-- GRANT EXECUTE ON DBMS_CLOUD_AI TO LAB;
-- CREATE PROCEDURE privilege is also required to create the lookup function.
