-- AI 프로파일 구성. 기존 POC_AI_PROFILE 속성을 복제해 판매/상품 SQL 프로파일을 만들고, Granite 조정 프로파일을 생성한다.
-- 전제: 기존 프로파일·SH 객체·DB에서 접근 가능한 Ollama endpoint. 최초 설치용이며 재생성/덮어쓰기 스크립트가 아니다.

WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET DEFINE OFF
SET SQLBLANKLINES ON
DECLARE a JSON_OBJECT_T:=JSON_OBJECT_T();v CLOB;objs JSON_ARRAY_T:=JSON_ARRAY_T();o JSON_OBJECT_T;
BEGIN
 FOR r IN (SELECT attribute_name,attribute_value FROM user_cloud_ai_profile_attributes WHERE profile_name='POC_AI_PROFILE') LOOP
  IF r.attribute_name IN ('temperature','max_tokens','conversation_length') THEN a.put(r.attribute_name,TO_NUMBER(r.attribute_value));ELSIF r.attribute_name='conversation' THEN a.put(r.attribute_name,LOWER(r.attribute_value)='true');ELSE a.put(r.attribute_name,r.attribute_value);END IF;
 END LOOP;
 FOR r IN (SELECT column_value n FROM TABLE(SYS.ODCIVARCHAR2LIST('PRODUCTS','SALES','CUSTOMERS','COUNTRIES','TIMES'))) LOOP o:=JSON_OBJECT_T();o.put('owner',USER);o.put('name',r.n);objs.append(o);END LOOP;
 a.put('object_list',objs);v:=a.to_clob();DBMS_CLOUD_AI.CREATE_PROFILE(profile_name=>'POC_V2_SQL_PROFILE',attributes=>v);
 objs:=JSON_ARRAY_T();o:=JSON_OBJECT_T();o.put('owner',USER);o.put('name','PRODUCTS');objs.append(o);a.put('object_list',objs);v:=a.to_clob();DBMS_CLOUD_AI.CREATE_PROFILE(profile_name=>'POC_V2_PRODUCTS_PROFILE',attributes=>v);
 DBMS_CLOUD_AI.CREATE_PROFILE(profile_name=>'POC_V2_AGENT_PROFILE',attributes=>'{"model":"granite4.1:8b","provider_endpoint":"http://service-ollama/v1","conversation":true,"conversation_length":30,"temperature":0,"max_tokens":2048}');
END;
/
