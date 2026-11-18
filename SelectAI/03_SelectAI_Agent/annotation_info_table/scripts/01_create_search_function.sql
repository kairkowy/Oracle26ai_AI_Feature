SET DEFINE OFF
SET SERVEROUTPUT ON
SET SQLBLANKLINES ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

-- No LLM and no dynamic SQL: resolves the input against actual data.
-- Ignore case and whitespace; preserve exact original English names in results.
-- Each product appears once even if several aliases normalize to the same term.
CREATE OR REPLACE FUNCTION std_agent_find_product (
  p_term IN VARCHAR2
) RETURN CLOB AUTHID CURRENT_USER
IS
  l_key VARCHAR2(2000);
  l_result JSON_OBJECT_T := JSON_OBJECT_T();
  l_rows JSON_ARRAY_T := JSON_ARRAY_T();
  l_item JSON_OBJECT_T;
  l_count PLS_INTEGER := 0;
  l_total PLS_INTEGER := 0;
BEGIN
  IF p_term IS NULL OR LENGTH(p_term) > 200 THEN
    l_result.put('status', 'INVALID_INPUT');
    l_result.put('message', 'Pass a product expression of 1 to 200 characters, not the whole question.');
    RETURN l_result.to_clob();
  END IF;
  l_key := REGEXP_REPLACE(UPPER(TRIM(p_term)), '[[:space:]]+', '');
  IF l_key IS NULL THEN
    l_result.put('status', 'INVALID_INPUT');
    RETURN l_result.to_clob();
  END IF;

  FOR r IN (
    SELECT p.prod_id, p.prod_name, p.prod_list_price, COUNT(*) OVER () AS total_matches
    FROM products p
    WHERE REGEXP_REPLACE(UPPER(TRIM(p.prod_name)), '[[:space:]]+', '') = l_key
       OR EXISTS (
         SELECT 1 FROM data_standard d
         WHERE d.prod_id = p.prod_id
         AND REGEXP_REPLACE(UPPER(TRIM(d.term_ko)), '[[:space:]]+', '') = l_key
       )
    ORDER BY p.prod_id
    FETCH FIRST 20 ROWS ONLY
  ) LOOP
    l_count := l_count + 1;
    l_total := r.total_matches;
    l_item := JSON_OBJECT_T();
    l_item.put('prod_id', r.prod_id);
    l_item.put('prod_name', r.prod_name);
    l_item.put('prod_list_price', r.prod_list_price);
    l_rows.append(l_item);
  END LOOP;

  l_result.put('input_term', p_term);
  l_result.put('normalized_term', l_key);
  l_result.put('source', 'PRODUCTS + DATA_STANDARD');
  l_result.put('match_count', l_total);
  l_result.put('returned_count', l_count);
  l_result.put('truncated', l_total > l_count);
  l_result.put('matches', l_rows);
  IF l_total = 1 THEN
    l_result.put('status', 'MATCH');
  ELSIF l_total > 1 THEN
    l_result.put('status', 'AMBIGUOUS');
    l_result.put('message', 'Do not select one candidate arbitrarily. Ask the user to identify a product.');
  ELSE
    l_result.put('status', 'NOT_FOUND');
    l_result.put('message', 'No registered product expression matched. Do not invent an English translation or a product ID.');
  END IF;
  RETURN l_result.to_clob();
END;
/
SHOW ERRORS FUNCTION std_agent_find_product

-- SQL*Plus may continue after CREATE FUNCTION compilation warnings; fail explicitly.
DECLARE
  l_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM user_errors
  WHERE name = 'STD_AGENT_FIND_PRODUCT' AND type = 'FUNCTION' AND attribute = 'ERROR';
  IF l_count > 0 THEN
    RAISE_APPLICATION_ERROR(-20103, 'STD_AGENT_FIND_PRODUCT has compilation errors.');
  END IF;
END;
/
