-- Optional first-time dictionary installation. DATA_STANDARD must not already exist.
-- Requires current sports-products SH sample (72 products) copied to the current user.
-- Inserts one illustrative Korean standard name and one synonym for each product.
-- Source product identifiers/names:
-- https://github.com/oracle-samples/db-sample-schemas/blob/main/sales_history/sh_populate.sql
-- No profile or Annotation is created by this preparation script.
SET DEFINE OFF
SET SERVEROUTPUT ON
SET SQLBLANKLINES ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

PROMPT 1. Create the product term dictionary
CREATE TABLE data_standard (
  prod_id        NUMBER NOT NULL,
  standard_value VARCHAR2(200 CHAR) NOT NULL,
  term_ko        VARCHAR2(200 CHAR) NOT NULL,
  term_type      VARCHAR2(10 CHAR) NOT NULL,
  CONSTRAINT data_standard_pk PRIMARY KEY (prod_id, term_ko),
  CONSTRAINT data_standard_product_fk FOREIGN KEY (prod_id)
    REFERENCES products (prod_id),
  CONSTRAINT data_standard_type_ck CHECK (term_type IN ('STANDARD', 'SYNONYM'))
);
CREATE INDEX data_standard_term_ix ON data_standard (term_ko, prod_id);
CREATE UNIQUE INDEX data_standard_name_uq ON data_standard (
  CASE WHEN term_type = 'STANDARD' THEN prod_id END
);

PROMPT 2. Insert two distinct Korean terms for each of the 72 products
DECLARE
  l_missing NUMBER;
  l_total NUMBER;
  PROCEDURE seed_product(
    p_id NUMBER, p_english VARCHAR2, p_korean VARCHAR2, p_alias VARCHAR2
  ) IS
    l_actual products.prod_name%TYPE;
  BEGIN
    SELECT prod_name INTO l_actual FROM products WHERE prod_id = p_id;
    -- Validate identity without rejecting case-only or surrounding-space differences.
    -- Persist the exact value read from PRODUCTS, not the seed literal or UPPER(value).
    IF UPPER(TRIM(l_actual)) <> UPPER(TRIM(p_english)) OR l_actual IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001,
        'Unexpected product name for PROD_ID=' || p_id || ': ' || l_actual);
    END IF;
    INSERT INTO data_standard VALUES (p_id, l_actual, p_korean, 'STANDARD');
    INSERT INTO data_standard VALUES (p_id, l_actual, p_alias, 'SYNONYM');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20002, 'Missing expected product: ' || p_id || ' / ' || p_english);
  END;
BEGIN
  seed_product(14, 'Pitching Machine and Batting Cage Combo', '피칭 머신과 타격 케이지 세트', '투구 기계 타격 연습장 패키지');
  seed_product(21, 'Speed Trainer Bats and Training Program', '스피드 트레이너 배트와 훈련 프로그램', '스윙 속도 훈련 배트 프로그램 세트');
  seed_product(22, 'MLB Official Game Baseball w/ Display Case', '전시 케이스 포함 MLB 공식 경기구', '진열함 포함 메이저리그 공인 야구공');
  seed_product(46, '2 Competition Grade NFHS Baseballs', 'NFHS 경기용 야구공 2개', '미국 고교연맹 규격 시합구 두 개 세트');
  seed_product(47, '6 Gallon Empty Ball Bucket', '6갤런 빈 야구공 버킷', '6갤런 야구공 보관용 빈 통');
  seed_product(127, 'Genuine Series MIX Wood Bat', '제뉴인 시리즈 믹스 목재 배트', '제뉴인 MIX 나무 야구방망이');
  seed_product(128, 'Slugger Youth Series Maple Bat', '슬러거 유소년 시리즈 메이플 배트', '슬러거 주니어 단풍나무 야구방망이');
  seed_product(129, 'Pro Maple Bat', '프로 메이플 배트', '프로 단풍나무 야구방망이');
  seed_product(130, 'Pro Maple Youth Bat', '프로 메이플 유소년 배트', '프로 주니어 단풍나무 야구방망이');
  seed_product(19, 'Cricket Bat Bag', '크리켓 배트 가방', '크리켓 방망이 보관백');
  seed_product(23, 'Plastic Cricket Bat', '플라스틱 크리켓 배트', '합성수지 크리켓 방망이');
  seed_product(28, 'English Willow Cricket Bat', '잉글리시 윌로 크리켓 배트', '영국산 버드나무 크리켓 방망이');
  seed_product(30, 'Linseed Oil', '아마인유', '크리켓 배트 관리용 아마씨 오일');
  seed_product(31, 'Fiber Tape', '섬유 테이프', '크리켓 배트 보강용 파이버 테이프');
  seed_product(40, 'Team shirt', '서인도제도 크리켓 대표팀 셔츠', '웨스트인디스 크리켓 팀 유니폼');
  seed_product(41, 'Team shirt', '남아프리카공화국 크리켓 대표팀 셔츠', '남아공 크리켓 팀 유니폼');
  seed_product(42, 'Team shirt', '뉴질랜드 크리켓 대표팀 셔츠', '뉴질랜드 크리켓 팀 유니폼');
  seed_product(43, 'Team shirt', '호주 크리켓 대표팀 셔츠', '오스트레일리아 크리켓 팀 유니폼');
  seed_product(44, 'Team shirt', '인도 크리켓 대표팀 셔츠', '인디아 크리켓 팀 유니폼');
  seed_product(45, 'Team shirt', '잉글랜드 크리켓 대표팀 셔츠', '잉글랜드 크리켓 팀 유니폼');
  seed_product(48, 'Indoor Cricket Ball', '실내 크리켓 공', '인도어 크리켓 볼');
  seed_product(113, 'Cricket Ball', '가죽 크리켓 공', '크리켓 가죽 경기구');
  seed_product(114, 'Cricket Ball - Training Ball', '훈련용 크리켓 공', '크리켓 연습구');
  seed_product(115, 'Plastic - Beach Cricket Ball', '플라스틱 비치 크리켓 공', '해변용 합성수지 크리켓 볼');
  seed_product(116, 'Catchers Helmet', '포수용 헬멧', '포수 보호 투구');
  seed_product(117, 'Plastic - Beach Cricket Wickets', '플라스틱 비치 크리켓 위켓', '해변 크리켓용 합성수지 위켓');
  seed_product(118, 'Cricket Bails', '크리켓 베일', '크리켓 위켓 상단 가로막대');
  seed_product(119, 'Cricket Bails - Junior', '주니어 크리켓 베일', '유소년 크리켓 위켓 가로막대');
  seed_product(120, 'Cricket Peak Cap', '크리켓 챙모자', '크리켓 피크 캡');
  seed_product(121, 'Cricket - Athletic Guard Cup', '크리켓 보호 컵', '크리켓 선수용 낭심 보호대');
  seed_product(122, 'Wide Brim Hat', '크리켓 넓은 챙 모자', '크리켓 와이드 브림 햇');
  seed_product(123, 'Helmet', '크리켓 헬멧', '크리켓 타자용 보호 투구');
  seed_product(124, 'Wicket Keeper Gloves', '위켓키퍼 장갑', '크리켓 포수용 글러브');
  seed_product(125, 'Bucket Hat', '크리켓 버킷햇', '크리켓 벙거지 모자');
  seed_product(126, 'Spiked Shoes', '크리켓 스파이크화', '크리켓 징 운동화');
  seed_product(15, 'Right-Handed Graphite Shaft Iron Set', '오른손잡이용 그라파이트 샤프트 아이언 세트', '우타용 흑연 샤프트 골프 아이언 세트');
  seed_product(18, 'Lithium Electric Golf Caddy', '리튬 배터리 전동 골프 캐디', '리튬 전지 전동 골프 카트');
  seed_product(13, 'Soccer Goal - Portable', '이동식 축구 골대', '휴대용 축구 골문');
  seed_product(17, 'Soccer Goal - Official', '공식 규격 축구 골대', '정규 경기용 축구 골문');
  seed_product(131, 'Soccer Ball - Size 4', '4호 축구공', '유소년용 사이즈 4 축구공');
  seed_product(132, 'Soccer Ball - Size 5', '5호 축구공', '성인용 사이즈 5 축구공');
  seed_product(133, 'Goal Keeper Gloves', '골키퍼 장갑', '축구 골키퍼 글러브');
  seed_product(134, 'Shin Guards', '축구 정강이 보호대', '축구 신가드');
  seed_product(135, 'Gear Bag', '축구 장비 가방', '축구용품 수납백');
  seed_product(136, 'Soccer Jersey', '축구 유니폼 상의', '축구 저지');
  seed_product(137, 'Soccer Cleats - Junior', '주니어 축구화', '유소년용 축구 스파이크화');
  seed_product(138, 'Soccer Cleats - Adult', '성인 축구화', '성인용 축구 스파이크화');
  seed_product(16, 'Sonic Core Graphite Racquet', '소닉 코어 그라파이트 라켓', '소닉코어 흑연 테니스 라켓');
  seed_product(20, 'Match Used Autograph Racquet', '경기 사용 사인 라켓', '선수 친필 사인 실사용 테니스 라켓');
  seed_product(29, 'Limited Edition Racquet', '한정판 테니스 라켓', '리미티드 에디션 라켓');
  seed_product(139, 'Tennis Balls Heavy Duty Felt 3', '고내구성 펠트 테니스공 3개', '헤비 듀티 펠트 테니스 볼 세 개 세트');
  seed_product(140, 'Tennis Strings Natural Gut', '천연 거트 테니스 스트링', '천연 소재 테니스 라켓 줄');
  seed_product(141, 'Tennis Strings Synthetic Gut', '합성 거트 테니스 스트링', '인조 거트 테니스 라켓 줄');
  seed_product(142, 'Tennis Strings Hybrids', '하이브리드 테니스 스트링', '혼합 소재 테니스 라켓 줄');
  seed_product(143, 'Tennis Strings Polyester', '폴리에스터 테니스 스트링', '폴리 소재 테니스 라켓 줄');
  seed_product(144, 'Tennis Grip Overgrip Tacky', '점착형 테니스 오버그립', '미끄럼 방지 점착 라켓 덧그립');
  seed_product(145, 'Practice Tennis Balls', '연습용 테니스공', '테니스 훈련구');
  seed_product(146, 'Regular Duty Tennis Balls', '레귤러 듀티 테니스공', '일반 코트용 테니스 볼');
  seed_product(147, 'Cushioned Grip', '쿠션 그립', '충격 흡수 라켓 손잡이 그립');
  seed_product(148, 'Tennis Balls 12 Pack', '테니스공 12개 묶음', '테니스 볼 열두 개 세트');
  seed_product(24, 'Endurance Coolcore 1/2 Zip Pullover', '엔듀런스 쿨코어 반집업 풀오버', '엔듀런스 쿨코어 하프집업 상의');
  seed_product(25, '5 Point Batting Tee', '5포인트 배팅 티', '다섯 지점 타격 연습대');
  seed_product(26, 'Pro Style Batting Tee', '프로 스타일 배팅 티', '프로형 타격 연습대');
  seed_product(27, 'Bucket of 24 Synthetic Baseballs', '합성 야구공 24개 버킷', '인조 소재 야구공 스물네 개 통 세트');
  seed_product(32, 'Bucket of 24 Leather Baseballs', '가죽 야구공 24개 버킷', '천연가죽 야구공 스물네 개 통 세트');
  seed_product(33, 'Baseball Is Life Cap', '베이스볼 이즈 라이프 모자', '야구가 인생이다 문구 야구모자');
  seed_product(34, '11.5" Youth Triple Stripe Series Glove', '11.5인치 유소년 트리플 스트라이프 글러브', '주니어 삼선 시리즈 11.5인치 야구 장갑');
  seed_product(35, 'Catchers Mitt', '포수 미트', '야구 포수용 장갑');
  seed_product(36, '12" Premium Series Glove', '12인치 프리미엄 시리즈 글러브', '프리미엄 12인치 야구 장갑');
  seed_product(37, '12.75" Premium Series Glove', '12.75인치 프리미엄 시리즈 글러브', '프리미엄 12.75인치 야구 장갑');
  seed_product(38, '11" Youth Field Master Glove', '11인치 유소년 필드 마스터 글러브', '주니어 필드마스터 11인치 야구 장갑');
  seed_product(39, '13" Field Master Series Glove', '13인치 필드 마스터 시리즈 글러브', '필드마스터 13인치 야구 장갑');

  SELECT COUNT(*) INTO l_missing
  FROM products p
  WHERE (SELECT COUNT(DISTINCT d.term_ko) FROM data_standard d
         WHERE d.prod_id = p.prod_id) < 2;
  IF l_missing > 0 THEN
    RAISE_APPLICATION_ERROR(-20003,
      'Products without two Korean terms: ' || l_missing || '. Extend the seed list first.');
  END IF;
  SELECT COUNT(*) INTO l_total FROM data_standard;
  DBMS_OUTPUT.PUT_LINE('Inserted Korean terms: ' || l_total || ' (expected 144).');
  COMMIT;
END;
/
