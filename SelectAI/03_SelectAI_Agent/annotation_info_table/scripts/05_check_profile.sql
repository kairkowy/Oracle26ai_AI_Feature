-- Read-only: compare the Agent settings with previously working lab profiles.
SET DEFINE OFF
SET LONG 10000
SET LINESIZE 200
COLUMN profile_name FORMAT A30
COLUMN attribute_name FORMAT A25
COLUMN attribute_value FORMAT A90
SELECT profile_name, attribute_name, attribute_value
FROM user_cloud_ai_profile_attributes
WHERE UPPER(profile_name) IN (
  'STD_PRODUCT_AGENT_PROFILE', 'SELECTAI_PRODUCTS_STD',
  'SELECTAI_PRODUCTS_SEARCH', 'SELECTAI_PRODUCTS_ANN'
)
AND LOWER(attribute_name) IN ('provider', 'provider_endpoint', 'model')
ORDER BY profile_name, attribute_name;

-- On the DB server/container, inspect the HTTP response body:
-- curl -i -sS --max-time 30 http://service-ollama/v1/models
-- curl -i -sS --max-time 120 http://service-ollama/v1/chat/completions \
--   -H 'Content-Type: application/json' \
--   -d '{"model":"ACTUAL_INSTALLED_MODEL_ID","messages":[{"role":"user","content":"Reply OK"}],"stream":false}'
-- JSON reporting model not found: fix the model ID, not the path.
-- Proxy HTML/plain route 404: inspect proxy/upstream routing and logs.
-- Change /v1 only after checking how the installed Oracle RU constructs its URL.
-- Observed failing URI is /v1/chat/completions, not /v1/v1/chat/completions.
