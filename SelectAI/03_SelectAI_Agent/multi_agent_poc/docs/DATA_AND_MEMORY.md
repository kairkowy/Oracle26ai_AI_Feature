# 데이터 구조·표준화·메타정보·메모리

[목차](../README.md)

![데이터 관계와 업무 메모리](../diagrams/data-model.svg)

## 원천 SH 데이터: 기존 객체를 읽어 재사용

| 테이블 | 검증 시 행 수 | 주요 사용 컬럼 | 역할·논리 관계 |
|---|---:|---|---|
| PRODUCTS | 72 | PROD_ID, PROD_NAME, PROD_LIST_PRICE, PROD_CATEGORY, PROD_SUBCATEGORY | 상품 ID당 한 행의 기준정보. |
| SALES | 918,843 | PROD_ID, CUST_ID, TIME_ID, AMOUNT_SOLD, QUANTITY_SOLD | 판매 행의 사실 데이터. PROD_ID→PRODUCTS, CUST_ID→CUSTOMERS, TIME_ID→TIMES. |
| CUSTOMERS | 55,500 | CUST_ID, CUST_GENDER, COUNTRY_ID | 고객 성별 M/F 및 국가 연결. COUNTRY_ID→COUNTRIES. |
| COUNTRIES | 35 | COUNTRY_ID, COUNTRY_NAME | 구매 고객 국가 기준정보. |
| TIMES | 1,826 | TIME_ID, CALENDAR_YEAR | 날짜·연도·연월 차원. |

SALES 한 행을 하나의 주문이나 상품 한 개와 동일시하지 않는다. 상품 평균 정가와 판매행 평균 매출은 다른 지표다. 월별 집계는 YYYY-MM로 연도를 포함한다. SH에는 통화 컬럼이 없어 USD는 **POC 가정**으로 표시하며 실제 원천 통화를 검증한 것으로 해석하지 않는다. 환율 변환은 하지 않는다.

## 표준화 계층: 표현을 실제 값에 연결

| 테이블 | 주요 키·컬럼 | 데이터 의미 |
|---|---|---|
| POC_STD_DOMAIN | domain_key PK, field_key, description | product, gender, country, category, currency의 5개 표준화 영역과 업무 필드 연결. |
| POC_STD_VALUE | (domain_key,value_key) PK, db_value, ko_name, en_name | 117개 기준값. 내부 식별 키·DB 조건값·한영 표시명을 분리한다. product의 value_key는 실제 상품 ID 문자열이다. |
| POC_STD_ALIAS | (domain_key,value_key,alias_text) PK/FK, alias_norm, language, match_mode | 469개 한영 별칭·동의어. 정규화 검색 문자열과 일치 규칙을 저장한다. 여러 상품에 같은 영어명이 연결될 수 있다. |
| POC_QUESTION_TERM | term_key PK, term_text, term_kind, target_key, language, match_mode | 96개 업무 질의 표현. “매상”→revenue 같은 지표·집계·동작 힌트다. 실제 상품 값 사전과 목적이 다르다. |

POC_STANDARD.norm/resolve_value/scan_question/question_hints가 표준화와 의미 힌트를 구성하고 localized_rows가 답변 표시를 처리한다. POC_PRODUCT_RESOLVE는 사전 후보의 상품 ID로 실제 PRODUCTS 명칭·정가를 읽는다. 단순한 모델 번역 결과를 상품 ID로 간주하지 않는다.

예를 들어 “미합중국 여자 고객이 구매한 야구용품의 매상 합계”는 “미합중국”을 United States of America, “여자”를 F, “야구용품”을 Baseball에 연결한다. “매상”은 실제 값이 아니라 revenue 지표의 표현이며 AMOUNT_SOLD 합계로 해석한다. “프로 메이플 배트”는 상품 ID 129로 연결한다. 원문과 기준값을 함께 보관해 출력에서 원문 표현을 유지한다.

## 업무 메타정보: SQL 생성·검증의 계약

| 테이블 | 건수 | 주요 컬럼·역할 |
|---|---:|---|
| POC_AI_DATASET | 2 | dataset_key, base_from, description, unique_key_field. products는 상품당 한 행, sales는 판매 지표 분석. |
| POC_AI_FIELD | 13 | field_key, sql_expression, data_type, field_kind, allowed_aggs, default_agg, required_join, description, dictionary_managed, standard_domain, label_ko. |
| POC_AI_DATASET_FIELD | 19 | (dataset_key,field_key). 데이터셋에 허용할 필드의 소속. |
| POC_AI_JOIN | 4 | (dataset_key,join_key), join_sql. 시간/고객국가 등 허용 조인. v2는 POC_SETTING 통화 CROSS JOIN 정의를 SQL 생성/검사 소스에서 제외한다. |
| POC_AI_OPERATOR | 11 | operator_key, sql_token, arity, data_types. =, <>, 범위/목록/NULL 등 연산자 계약. |
| POC_AI_AGGREGATE | 5 | aggregate_key, sql_template, label_prefix. SUM, AVG, MIN, MAX, COUNT_DISTINCT 및 표시 접두어. |
| POC_AI_POLICY | 9 | policy_key, number_value. 조회/보고 행 수, 계획 재시도, 후보 수와 매칭 정책. |
| POC_PROMPT | 1 | prompt_key, prompt_text, description. 기존 표준화 처리의 프롬프트 자산. v2 주요 생성·검토 프롬프트는 POC_V2_API 코드에도 있다. |
| POC_SETTING | 3 | setting_key, setting_value, description. 기존 프로파일명, 기준 통화 가정과 설명. |

위 표의 표준화 4개와 업무 메타정보 9개를 합한 **13개 테이블**은 전후 내용 해시가 동일했다. 건수는 검증 시점 스냅샷이며 새 환경의 고정 설치값이 아니다. 이 폴더는 해당 테이블·함수를 재생성하는 seed SQL을 포함하지 않는다. 새 환경은 기존 프로젝트에서 준비해야 한다.

대표 필드는 product_id/product_name/list_price/category/subcategory, revenue/quantity, country/gender, year/month/sale_date, currency다. currency의 메타 SQL 식은 기존 자산에 남아 있으나 v2 카탈로그에서는 USD 리터럴 가정으로 취급한다. 메타테이블을 모두 참조한다고 v2 SQL을 완전한 결정형 컴파일러로 생성하는 것은 아니다. 필드 소속·허용 소스·행 식별 검사는 코드에서 강제하고 의미 해석/SQL 생성에는 LLM을 사용한다.

## 메모리: 모델 이력과 영속 업무 상태 구분

| 계층 | 위치·설정 | 담는 내용·사용 원칙 |
|---|---|---|
| 사용자 요청 식별 | RUNS.conversation_id + client_turn_id | 사용자가 보는 대화 소속과 turn 재전송 키. 같은 문자열을 새 turn에 보내면 새 요청이다. |
| 영속 업무 메모리 | POC_V2_RUNS | 원문/유효 질문, revision, context, requirements, SQL과 승인·실행 CLOB, 원시 결과, 보고서, 이벤트, 실행 토큰/예산. 다음 단계와 사용자 답변의 근거다. |
| Native 실행 추적 | POC_V2_EXECS | 요청별 round_no, revision, Native conversation_id, 단계 전후 상태, Native 상태/출력/Task 스냅샷. 진단·감사용이며 승인 근거를 대신하지 않는다. |
| Native 런타임 포인터 | RUN_TEAM params.state_variables | request_id, request_revision을 Tool에 명시 전달. Worker 간 암묵적 공유 대화에 의존하지 않는다. |
| Human 지시 변수 | instruction_variables.human_question | 현재 저장 질문과 실제 후보를 해당 Human Task에 전달하는 입력. 영구 정답 메모리가 아니다. |
| Native 단기 문맥 | Agent 프로파일 conversation=true, conversation_length=30; 실행 대화 length=30 | 현재 Native 실행의 문맥 설정. Agent 속성 short_term_memory_length는 이 코드에서 명시하지 않고 환경 기본값을 사용한다. 설정 이름이 다르므로 동일한 메모리 저장소로 취급하지 않는다. |
| Team 장기 이력 길이 | long_term_memory_length=1 | Native Team의 이전 실행 이력 포함 범위 설정. 업무 지식 DB/벡터 검색/영구 정답 캐시를 만든다는 뜻이 아니다. |
| Tool 모델 대화 | POC_V2_API.ask에서 매 호출 별도 conversation_length=1 대화 | 요구 추출·생성·검토 대화를 분리하고 명시적 문맥을 넘긴다. 호출 후 이전 세션 대화 ID 복원. |

RUNS.request_id는 32자리 식별자이며 사용자 대화 ID, Native 실행 대화 ID와 다르다. RUNS와 EXECS는 FK로 연결된다. 한 요청에 여러 Native 실행 대화가 생길 수 있다. 이전 Native 출력에 “성공”이 있어도 승인된 동일 revision의 SQL과 결과가 없으면 성공을 공개하지 않는다.

## 보존과 운영 전 검토

현재 자동 purge/보존 주기·암호화 정책·사용자별 접근 분리·재시작 후 자동 복구 스케줄러는 구현하지 않았다. 대화·질문·원시 결과·Task 이력이 쌓이므로 운영 전 접근 권한과 보존 정책이 필요하다. “그중”, “같은 조건으로” 같은 이전 질문 참조를 자동 연결하는 대화형 분석 메모리는 이번 범위에 없다.
