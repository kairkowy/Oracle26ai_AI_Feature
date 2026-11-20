-- 공개 run/resume 사용 예. 동일 요청 재전송은 같은 turn ID, 새로운 질문은 새로운 turn ID를 사용한다.
-- 후보 선택에는 실제 응답의 request_id/revision/product_id를 사용한다. SQL 원문과 Native 출력은 진단/데이터 응답과 구분한다.

SET DEFINE OFF
SET LONG 200000
SET LONGCHUNKSIZE 200000
-- LAB에서는 검증 후 활성화한 POC_V2_TEAM을 사용한다.
-- 애플리케이션 클라이언트는 callTimeout과 취소 처리를 설정한다(client.cjs 참조).

-- 독립 요청에는 새 turn ID를, 동일 요청 재전송에는 같은 turn ID를 부여한다.
SELECT POC_V2_GATE.run(
 '프로 메이플 배트의 상품 ID와 상품명과 정가를 조회해줘.',
 'lab-session-001', 'turn-001'
) AS response FROM dual;

-- 판매 이력·표준화 동의어·업무 메타데이터 재사용
-- SELECT POC_V2_GATE.run('미합중국 여자 고객이 구매한 야구용품의 매상 합계를 조회해줘.','lab-session-001','turn-002') response FROM dual;

-- SQL만 작성: 데이터 조회 실행 없음
-- SELECT POC_V2_GATE.run('미합중국 여자 고객이 구매한 야구용품의 매상 합계 SQL만 작성해줘. 실행하지 말아줘.','lab-session-001','turn-003') response FROM dual;

-- 모호한 상품의 실제 후보 선택
-- SELECT POC_V2_GATE.run('Team shirt의 상품 ID와 상품명과 정가를 조회해줘.','lab-session-001','turn-004') response FROM dual;
-- SELECT POC_V2_GATE.resume('위 응답의 request_id',1,'실제 후보 상품 ID') response FROM dual;

-- 다섯 번째 질문: SQL 설명만 요청한다. 이번 v2 전체 Native 회귀 시험 미실시 경로.
-- SELECT POC_V2_GATE.run('미합중국 여자 고객이 구매한 야구용품의 매상 합계 SQL을 설명해줘. 실행하지 말아줘.','lab-session-001','turn-005') response FROM dual;

-- 확인용: raw_agent_output은 진단 전용이며 사용자 답변으로 사용하지 않는다.
-- SELECT request_id,revision,state,flow_steps,execution_attempts,last_error FROM POC_V2_RUNS ORDER BY created_at DESC FETCH FIRST 10 ROWS ONLY;
