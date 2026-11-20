-- 기존 LAB 데이터·표준화·메타데이터가 준비된 계정에서 수행하는 v2 최초 설치.
-- 이 폴더를 현재 디렉터리로 정한 SQL*Plus에서 @install.sql 실행. 재적재/삭제/기존 v2 마이그레이션은 수행하지 않는다.

@00_profiles.sql
@01_state.sql
@01a_executions.sql
@02_api.sql
@03_gateway.sql
@03a_cancel.sql
@04_agents.sql
