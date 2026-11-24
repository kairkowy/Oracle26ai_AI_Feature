# 검증 결과와 남은 항목

[목차](../README.md) · [공개 요약 JSON](../tests/results/summary.json)

검증일 2026-11-20. 기존 LAB v2 실행 결과를 정리했다. 이번 문서화·업로드 작업에서 모델 추론을 다시 수행한 결과는 아니다. 공개 요약은 실제 시험 산출물에서 통과 여부·기준값·시간·재사용 해시만 추출했다. 원시 대화/Task 출력과 DB 접속 정보를 저장소에 게시하지 않는다.

당시 환경은 DB 23.26.4.0.0, Ollama 0.17.7이며 Native 조정은 granite4.1:8b, Tool 내부 요구 해석·SQL 생성·검토는 기존 gemma2:9b를 사용했다. Granite 단독 SQL 생성 품질 시험이 아니다.

11월 20일 문서화 시에는 SQL 9개의 실행 내용이 원본과 동일함(독립 주석 제외), 상대 링크와 SVG 렌더링, Node 구문을 확인했다. [당시 정적 검사 기록](../tests/results/documentation-checks.json)을 보존한다. 11월 24일 개정에서는 설명 순서를 다시 구성하고 질문 표현을 “미국”으로 정리했다. DB 추론을 다시 실행한 것은 아니며, 집계 기준값은 11월 20일 동일 조건의 시험 결과다. [개정 정적 검사](../tests/results/documentation-revision-20261124.json)는 별도 기록한다.

| 시험 | 결과 | 실제 확인 |
|---|---|---|
| 요청·승인·동시성 보호 검사 | 20/20 통과 | turn 정체성, 상태 순서, stale revision, 승인 SQL/버전 변조, 위조 완료, 동시 SQL 1회, 32KB 초과 CLOB, 실제 후보, 취소 후 늦은 호출, 데이터셋·상품 ID·고유 키 등. |
| 상품 전체 Native | 통과 / 269.0초 | product_id=129, Pro Maple Bat, list_price=192.99. |
| 매출 전체 Native | 통과 / 266.7초 | revenue_sum=6063776.96. 원문 “매상” 표시 유지. |
| Human 후보 선택 후 API 재개 | 통과 | 실제 반환 후보 중 ID 41 → Team shirt / 44.99. revision 2, SQL 1회. |
| Human Worker 대기 | 관찰 | STANDARD_HUMAN_TASK WAITING_FOR_HUMAN. |
| 상위 Native Team 대기 | **실패** | SUCCEEDED 반환. 엄격 Human 시험 pass=false. |
| SHOWSQL 전체 Native | **미완료** | 검증 도구 세션 재시작으로 클라이언트 중단. 요청 폐기, SQL 실행 0회. 모델 시간 초과의 증거가 아님. |
| 클라이언트 경과 시간 취소 | 통과 | 2초 타이머 후 DB 정리 포함 11.016초에 CLIENT_DEADLINE_EXCEEDED / exit 1. FAILED·SQL 실행 0회. |
| 기존 자산 보존 | 통과 | 표준화·메타 13개 테이블 내용 해시/건수 동일, SH 재적재 없음. |

실행형 성공 경로는 사용자 report가 저장 보고서와 문자 단위로 같고, 승인·실행·현재 SQL CLOB가 같으며 SQL 실행은 요청당 1회였다. 실제 Supervisor와 Worker 3종의 이력·요청 ID 위임을 확인했다. 개발 중 발견한 상품 조회의 불필요한 SALES 조인/행 중복은 데이터셋 소스 제한·고유 키 검사로 보완했고 독립 SQL로 재검증했다.

상위 Human 상태를 공개 SET_EXECUTION_STATE로 WAITING_FOR_HUMAN으로 보정하려는 진단도 ORA-20053으로 거절됐다. 원인을 특정 프레임워크 버그로 확정하지 않는다. Gate는 NEEDS_CLARIFICATION을 기준으로 선택 전 SQL 생성을 막는다. 이는 API 흐름의 검증이며 Native 상위 대기가 정상이라는 뜻이 아니다.

## 독립 비교 SQL

~~~sql
-- 상품 기준값: 판매 이력 조인 없이 실제 상품 행 비교.
SELECT prod_id AS product_id, prod_name AS product_name,
       prod_list_price AS list_price
  FROM products WHERE prod_id = 129;

-- 국가/성별/상품분류 필터의 전체 매출. 상품별 GROUP BY를 추가하지 않는다.
SELECT SUM(s.amount_sold) AS revenue_sum
  FROM sales s
  JOIN products p ON p.prod_id = s.prod_id
  JOIN customers c ON c.cust_id = s.cust_id
  JOIN countries n ON n.country_id = c.country_id
  JOIN times t ON t.time_id = s.time_id
 WHERE c.cust_gender = 'F'
   AND n.country_name = 'United States of America'
   AND p.prod_category = 'Baseball';
~~~

## 한계

Ollama 관찰상 size_vram=0인 CPU 실행 환경이었으며 위 시간은 해당 LAB 관측값이다. 모든 자연어의 정확성·대규모 부하·장시간 장애 복구·사용자별 접근 분리·임의 SQL의 완전한 의미 검증을 보장하지 않는다. NARRATE/EXPLAINSQL 전체 Native, 실제 UI Human 응답, 질문 사이 지시어 해석은 이번 회귀 범위 밖이다. 운영 전 상위 Native Human 상태 연동과 이 범위를 추가 검증해야 한다.
