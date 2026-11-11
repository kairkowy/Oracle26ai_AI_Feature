-- Oracle AI Vector Search 샘플 데이터 준비
-- SQL*Plus/SQLcl 등에서 관리자/실습 계정 구간을 나누어 필요한 부분만 실행합니다.
-- 공통 전제와 권한·메모리 준비는 00.Setup.md를 먼저 확인합니다.
-- DIRECTORY 생성: 관리자. 테이블 생성·INSERT·인덱스 생성: 해당 실습 계정.
-- 기존 테이블이 있는 환경에서 전체 파일을 반복 실행하지 않습니다.
-- 파일 복사와 OS 읽기 권한 준비는 별도이며, 경로는 DB 서버 기준입니다.
-- HNSW 메모리와 재시작 여부는 DBA가 판단하며 이 파일은 DB를 종료하지 않습니다.

-- Similarity search(text) 데이터 준비


CREATE OR REPLACE DIRECTORY DOCPATH as '/home/oracle/labs/data/docs';

create table doc_store(docno varchar(10) primary key,doc_dept varchar(40),doc_cr_date varchar(20), doc_name varchar2(200),doc blob);

insert into doc_store(docno,doc_dept,doc_cr_date,doc_name,doc) values
('80-1','국방부',20250531,'국방정책실장 미국 상하원 대표단 면담',to_blob(bfilename('DOCPATH','국방정책실장미국상_하원대표단면담게시.hwpx'))),
('80-2','국방부',20250704,'화생방사 국제 화학방호교육',to_blob(bfilename('DOCPATH','화생방사국제화학방호교육게시.hwpx'))),
('80-3','국방부',20250711,'미국 B-52H 전략폭격기 전개하 한미일 공중훈 시행',to_blob(bfilename('DOCPATH','미국_B-52H전략폭격기전개하한미일공중훈련시행게시.hwpx'))),
('10-1','기획재정부',20250710,'광역 교통망 확충 3개 사업 예타 통과로 대도교통혼잡 해소기대',to_blob(bfilename('DOCPATH','광역교통망확충3개사업예타통과로대도시권교통혼잡해소기대.pdf'))),
('80-4','국방부',20250715,'2025일본방위백서기술내용관련항의',to_blob(bfilename('DOCPATH','2025일본방위백서기술내용관련항의게시.hwpx'))),
('20-1','행정안전부',20250715,'지방공무원 관리자 역량 끌어올릴 역량교육 전문가 양성한다',to_blob(bfilename('DOCPATH','지방공무원관리자역량끌어올릴역량교육전문가양성한다_지방자치역량센터.pdf'))),
('10-2','기획재정부',20250716,'임신공무원하루2시간모성보호시간사용보장',to_blob(bfilename('DOCPATH','임신공무원하루2시간모성보호시간사용보장_지방인사제도과.pdf'))),
('10-3','기획재정부',20250717,'하반기관세대응수출금융설명회개최',to_blob(bfilename('DOCPATH','하반기관세대응수출금융설명회개최.pdf'))),
('20-2','행정안전부',20250717,'고향사랑기부로 불어 넣은 지역 활력 2025년상반기모금결과공개',to_blob(bfilename('DOCPATH','고향사랑기부로불어넣은지역활력2025년상반기모금결과공개_균형발전진흥과.pdf'))),
('20-3','행정안전부',20250718,'간부 모시는날 등 불합리한 관행타파 지속 노력',to_blob(bfilename('DOCPATH','간부모시는날등불합리한관행타파지속노력_행정제도과.pdf'))),
('10-4','기획재정부',20250718,'공급망등 경제안보 분야에서 통상 환경변화를 고려한 대응전략 고도화',to_blob(bfilename('DOCPATH','통상환경변화를고려한대응전략고도화.pdf'))),
('20-4','행정안정부',20250720,'호우 피해지역 가전제품 무상수리팀 운영',to_blob(bfilename('DOCPATH','호우피해지역가전제품무상수리팀운영_복구지원과.pdf'))),
('20-5','행정안전부',20270721,'호우피해 수습을 위한 피해자 통합지원센터 운영',to_blob(bfilename('DOCPATH','호우피해수습을위한피해자통합지원센터운영_수습관리과.pdf'))),
('20-6','행정안전부',20250721,'민생회복 소비쿠폰 관련 시스템 운영상황 현장점검',to_blob(bfilename('DOCPATH','민생회복소비쿠폰관련시스템운영상황현장점검_디지털정부기획과.pdf'))),
('80-5','국방부',20250721,'사이버 작전사령부 美 사이버플래그훈련 참가',to_blob(bfilename('DOCPATH','사이버작전사령부美사이버플래그훈련참가게시.hwpx'))),
('20-7','행정안전부',20250722,'물놀이 사망 7월 하순에 최다 안전수칙지키며 안전하게 물놀이즐겨요',to_blob(bfilename('DOCPATH','물놀이사망7월하순에최다안전수칙지키며안전하게물놀이즐겨요_예방안전제도과.pdf')));
COMMIT;

create table if not exists doc_store_chunks(docno varchar(10), chunked_id number, chunked_data varchar2(4000), embed_vector vector);
alter table doc_store_chunks add constraint pk_chunk primary key(docno,chunked_id);

-- Similarity search(image) 데이터 준비

CREATE OR REPLACE DIRECTORY IMGPATH as '/home/oracle/labs/data/images';
create table if not exists img_tbl(
    imgno number,
    img_category varchar(50),
    img_category_detail varchar(50),
    img blob,
    img_v vector);
alter table img_tbl add constraint pk_imgs primary key(imgno);

insert into img_tbl(imgno,img_category,img_category_detail,img) values
(100,'fruits','apple',to_blob(bfilename('IMGPATH','apple_1.jpeg'))),
(101,'fruits','apple',to_blob(bfilename('IMGPATH','apple_2.jpeg'))),
(102,'fruits','apple',to_blob(bfilename('IMGPATH','apple_3.jpeg'))),
(103,'fruits','banana',to_blob(bfilename('IMGPATH','banana_1.jpeg'))),
(104,'fruits','banana',to_blob(bfilename('IMGPATH','banana_2.jpeg'))),
(105,'fruits','banana',to_blob(bfilename('IMGPATH','banana_3.jpeg'))),
(106,'fruits','kiwi',to_blob(bfilename('IMGPATH','kiwi_1.jpeg'))),
(107,'fruits','kiwi',to_blob(bfilename('IMGPATH','kiwi_2.jpeg'))),
(108,'fruits','kiwi',to_blob(bfilename('IMGPATH','kiwi_3.jpeg'))),
(109,'fruits','mango',to_blob(bfilename('IMGPATH','mango_1.jpeg'))),
(110,'fruits','mango',to_blob(bfilename('IMGPATH','mango_2.jpeg'))),
(112,'fruits','mango',to_blob(bfilename('IMGPATH','mango_3.jpeg'))),
(113,'fruits','orange',to_blob(bfilename('IMGPATH','orange_1.jpeg'))),
(114,'fruits','orange',to_blob(bfilename('IMGPATH','orange_2.jpeg'))),
(115,'fruits','orange',to_blob(bfilename('IMGPATH','orange_3.jpeg'))),
(116,'fruits','pineapple',to_blob(bfilename('IMGPATH','pineapple_1.jpeg'))),
(117,'fruits','pineapple',to_blob(bfilename('IMGPATH','pineapple_2.jpeg'))),
(118,'fruits','pineapple',to_blob(bfilename('IMGPATH','pineapple_3.jpeg'))),
(119,'fruits','strawberry',to_blob(bfilename('IMGPATH','strawberries_1.jpeg'))),
(120,'fruits','strawberry',to_blob(bfilename('IMGPATH','strawberries_2.jpeg'))),
(121,'fruits','strawberry',to_blob(bfilename('IMGPATH','strawberries_3.jpeg'))),
(122,'fruits','cherry',to_blob(bfilename('IMGPATH','cherry_1.jpeg'))),
(123,'fruits','cherry',to_blob(bfilename('IMGPATH','cherry_2.jpeg'))),
(124,'fruits','cherry',to_blob(bfilename('IMGPATH','cherry_3.jpeg'))),
(125,'fruits','watermelon',to_blob(bfilename('IMGPATH','watermelon_.jpeg'))),
(126,'fruits','watermelon',to_blob(bfilename('IMGPATH','watermelon_2.jpeg'))),
(127,'fruits','watermelon',to_blob(bfilename('IMGPATH','watermelon_3.jpeg'))),
(501,'animals','cat',to_blob(bfilename('IMGPATH','Black_Cat.jpg'))),
(502,'animals','cow',to_blob(bfilename('IMGPATH','Brown_Cow.jpg'))),
(503,'animals','cow',to_blob(bfilename('IMGPATH','Brown_Cow2.jpg'))),
(504,'animals','dog',to_blob(bfilename('IMGPATH','Brown_Dog.jpg'))),
(505,'animals','dog',to_blob(bfilename('IMGPATH','Brown_Dogs.jpg'))),
(506,'animals','cat',to_blob(bfilename('IMGPATH','cat_20.jpg'))),
(507,'animals','cat',to_blob(bfilename('IMGPATH','cat_40.jpg'))),
(508,'animals','cat',to_blob(bfilename('IMGPATH','White_Cat.jpg'))),
(509,'animals','tiger',to_blob(bfilename('IMGPATH','Tiger.jpg'))),
(510,'animals','tiger',to_blob(bfilename('IMGPATH','Tiger2.jpg'))),
(901,'cars','jeep',to_blob(bfilename('IMGPATH','Jeep_GrandCherokee.jpg'))),
(902,'cars','BMW',to_blob(bfilename('IMGPATH','BMW_502d.jpg'))),
(903,'cars','G7',to_blob(bfilename('IMGPATH','HD_G7.jpg')));
COMMIT;

-- RAG 데이터 준비
-- 문서 정보 테이블 준비

CREATE OR REPLACE DIRECTORY RAGDIR as '/home/oracle/labs/data/docs/rag';

create table rag_tbl(
    id number primary key,
    doc blob);

insert into rag_tbl(id,doc) values
(2,to_blob(bfilename('RAGDIR','SPRi_AI_202404.pdf')));
insert into rag_tbl(id,doc) values
(3,to_blob(bfilename('RAGDIR','소프트웨어_분리발주_매뉴얼_개정배포_16.7.pdf')));
commit;

SELECT DBMS_LOB.SUBSTR(DBMS_VECTOR_CHAIN.UTL_TO_TEXT(
  TO_BLOB(BFILENAME('RAGDIR','SPRi_AI_202404.pdf'))), 1000, 1) AS text_preview
FROM dual;

-- 2-1 RAG_DOC 데모 테이블

-- 청크 저장용 테이블 생성
create table if not exists rag_tbl_v(
문서번호 number,
청크ID number,
문서내용 varchar2(4000),
벡터 vector);

create index rag_tbl_v_key ON rag_tbl_v(문서번호,청크ID);


-- 2-2 RAG_DB 데모 테이블
-- 테이블
create table broad_tbl (보도번호 number, 부처명 varchar2(40), 보도제목 varchar2(200), 주무부서 varchar2(100), 보도일자 varchar(20), embed_vector vector);
alter table  broad_tbl add constraint pk_no primary key (보도번호,부처명);

insert into broad_tbl (보도번호 , 부처명 , 보도제목 , 주무부서 , 보도일자 , embed_vector) values
(17140,'행정안전부','(보도참고자료) 민생회복 소비쿠폰, 7월 31일 13시 기준 국민 10명 중 9명 신청','재정정책과','2025-07-31',null),
(17139,'행정안전부','AI가 보이스피싱 사기 대본 분석하고 키워드 추출해 범죄조직 잡는다','디지털과','2025-07-31',null),
(17138,'행정안전부','지방보조사업 업무가 궁금하면 보탬e에서 실시간으로 상담하세요','지방재정보조금정보과','2025-07-31',null),
(17137,'행정안전부','"광복의 감동, 기록으로 다시 만나다" 광복 80년 기념 "기록사랑 공모전" 개최','서비스정책과','2025-07-31',null),
(17136,'행정안전부','광주지역 지방의회 맞춤형 연수 실시','지방의정연수센터','2025-07-31',null),
(17135,'행정안전부','하천·계곡 내 불법 점용시설 단속을 통해 국민 불편 해소와 안전을 함께 챙긴다','재난경감과','2025-07-30',null),
(17134,'행정안전부','7.16.~20. 호우 피해지역 재난대책비 복구계획수립 전 246.2억원 우선 교부','복구지원과','2025-07-30',null),
(17133,'행정안전부','여름휴가, 물놀이사고·폭염·식중독 특히 조심!','예방안전제도과','2025-07-30',null),
(17132,'행정안전부','자동차 폐차 의뢰 시 인감증명서 안 내도 된다','주민과','2025-07-30',null),
(17131,'행정안전부','딥페이크 막는 AI, 범죄 수사 새 길 연다','공공지능데이터분석과','2025-07-30',null),
(17130,'행정안전부','세계로 나가는 인천공항에서 광복 80년 기념 태극기 달기 캠페인 열어','의정담당관','2025-07-30',null),
(17129,'행정안전부','청년의 목소리로 지방자치를 외치다! "지방자치 청년정책 경진대회" 개최','자치분권제도과','2025-07-30',null),
(17128,'행정안전부','휴가철 물놀이 사고, 기본수칙 준수로 막을 수 있습니다','재난안전점검과','2025-07-29',null),
(17127,'행정안전부','(보도참고자료) 「민생회복 소비쿠폰」 가맹점, 민간 지도 앱에서 확인할 수 있습니다','공공서비스혁신과',' 2025-07-29',null),
(17126,'행정안전부','2025년도 국민 안전교육 실태점검 결과, 9개 우수기관 선정','안전문화교육과','2025-07-29',null),
(17125,'행정안전부','국제 재난협력 확대를 위한 APEC 재난분야 회의 개최','재난안전APEC지원단','2025-07-29',null),
(17124,'행정안전부','공공데이터로 기업 연구·개발 지원, "국가중점데이터" 본격 개방 착수','공공지능데이터정책과','2025-07-29',null),
(17123,'행정안전부','행정안전부, 민생회복 소비쿠폰 집행 및 지방소멸 대응 현장 점검','자치행정과','2025-07-28',null),
(17122,'행정안전부','디지털 관광주민증 민간 앱으로 이용하세요','공공서비스혁신과','2025-07-28',null),
(17121,'행정안전부','국민주권 드높이는 "광복 80주년" 기념행사','의정담당관','2025-07-28',null),
(12942,'국방부','국방부장관, 폴란드 무명용사의 묘 헌화 및 방산업체 간담회 실시','국제정책관실 국제정책과, 전력정책국 방위산업수출기획과','2025-08-01',null),
(12941,'국방부','안규백 국방부장관, 헤그세스 미국 국방장관과 취임 후 첫 공조통화','국제정책관실 미국정책과','2025-07-31',null),
(12940,'국방부','국방부차관, 응급의료체계 현장확인','인사복지실 보건정책과','2025-07-30',null),
(12939,'국방부','국방부장관, 첫 국방외교로 폴란드 방문','국제정책관실 국제정책과, 전력정책국 방위산업수출기획과','2025-07-30',null),
(12937,'국방부','국방부장관, 취임 후 첫 현장점검','정책관리과','2025-07-28',null),
(12936,'국방부','국방부 인사기획관 신규 임용','차관실 운영지원과','2025-07-28',null),
(12935,'국방부','"변함없는 우정" 2025 한미 친선 태권도대회','인사기획관실 병영정책과','2025-07-28',null),
(12934,'국방부','국방부장관, 취임 후 첫 전군주요지휘관회의 주관','정책기획관실 정책기획과','2025-07-25',null),
(12933,'국방부','‘소통하는 국방’ 실현을 위한 첫걸음, 국방부 제6기 혁신어벤져스 출범','기획관리관실   혁신행정과','2025-07-24',null),
(12932,'국방부','한미 군수협력위원회, 국내 방산업체 참여 MRO 시범사업 대상으로 시누크(CH-47) 엔진 선정','자원관리실 군수기획과','2025-07-22',null),
(12931,'국방부','발굴된 6·25전사자 유품 보존처리… 문화유산 가치 확립에 첫걸음','유해발굴감식단 계획운영처','2025-07-22 ',null),
(12930,'국방부','사이버작전사령부, 사이버 플래그 훈련 참가','사이버작전사령부 기획과','2025-07-21',null),
(12929,'국방부','국방부와 금융감독원이 함께 하는 국방재정담당자 금융연수 첫 실시','기획조정실 재정회계과','2025-07-17',null),
(12928,'국방부','2025 일본 방위백서 기술내용 관련 항의','국제정책관실 동북아정책과','2025-07-15',null),
(12927,'국방부','미국 B-52H 전략폭격기 전개 하 한미일 공중훈련 시행','국제정책관실 미국정책과','2025-07-11',null),
(12926,'국방부','민관군이 첨단기술로 함께 그리는 국방 장비관리의 미래','군수관리관실 장비관리과','2025-07-10' ,null),
(12925,'국방부','“재난이 곧 안보상황”산불과의 전투, 국방부-산림청이 합동 대응한다','군수관리관실 재난안전관리과','2025-07-09' ,null),
(12924,'국방부','추서 예우 강화, 추서 진급된 계급 따라 유족급여 올린다','보건복지관실 군인재해보상과','2025-07-08',null),
(12923,'국방부','2025년도 군무원 채용 필기시험 전국에서 시행','인사기획관실 군무원채용팀','2025-07-04',null),
(28807,'산업자원부','한국형 차세대 전력망 구축 본격 착수','신산업분산에너지과','2025-07-31',null),
(28806,'산업자원부','환경‧사회‧지배구조(ESG) 경영 강화로 지속가능한 성장 대비','해외투자과','2025-07-31',null),
(28805,'산업자원부','(참고자료)미주통상과, 한미 관세협상 타결, 대미 수출 불확실성 해소','미주통상과','2025-07-31'  ,null),
(28804,'산업자원부','(참고자료)호남권 허수사업자 회수물량 170.7㎿ 배분 완료','전력계통혁신과','2025-07-30',null),
(28803,'산업자원부','25년 상반기 및 6월 주요 유통업체 매출 동향','유통물류과','2025-07-30',null),
(28802,'산업자원부','산업AI 솔루션 도입으로 제조기업의 AX(인공지능 전환) 가속화','산업인공지능혁신과','2025-07-30',null),
(28801,'산업자원부','2025 APEC, 한국의 리더십으로 인공지능(AI)과 통상의 미래 논의를 이끌다','다자통상협력과','2025-07-30',null),
(28800,'산업자원부','산업단지 초광역 산학연협의체 발전포럼 개최','입지총괄과','2025-07-30',null),
(28799,'산업자원부','새 정부 탄소중립산업 마스터플랜 수립 착수','에너지기술과','2025-07-29',null),
(28798,'산업자원부','전북·경남 기회발전특구 추가 지정','지역경제진흥과','2025-07-29',null),
(28797,'산업자원부','탄소중립산단 대표모델 구축사업 공모 개시','입지총괄과','2025-07-28',null),
(28796,'산업자원부','(참고자료)통상정책총괄과, 정부 한미 고위급 협의를 이어가며 관세 협상 돌파구 마련에 총력','통상정책총괄과','2025-07-25',null),
(28795,'산업자원부','집중호우 및 혹서기 대비 광산안전 현장점검','석탄산업과','2025-07-25',null),
(28794,'산업자원부','산업부, ‘통상환경 변화에 대응한 새로운 FDI 정책 방향’ 모색 ','투자정책과','2025-07-25',null),
(28793,'산업자원부','(참고자료)통상정책총괄과, 김정관 산업장관, 美 러트닉 상무장관과 심도 있는 관세협상 진행', '통상정책총괄과','2025-07-25',null),
(28792,'산업자원부','무역위, 일(日)‧중(中) 열간압연에 잠정 덤핑방지관세 부과 건의','무역구제정책과','2025-07-24',null),
(28791,'산업자원부','K-방산, 글로벌 4대 강국 도약 위해 민군 맞손 잡다','첨단민군혁신지원과','2025-07-24',null),
(28790,'산업자원부','(참고자료)다자통상협력과, 최성요 주제네바 차석대사, 세계무역기구(WTO) 우즈베키스탄 가입작업반 의장 수임','다자통상협력과','2025-07-24',null),
(28789,'산업자원부','AI 기반 소재 개발, 데이터 표준화로 가속','전기전자정보표준과','2025-07-24',null),
(28788,'산업자원부','(참고자료)통상정책총괄과, 산업부 장관, 한미 관세협상 진전 및 산업 에너지 협력 강화를 위해 방미','통상정책총괄과','2025-07-23',null);
COMMIT;


-- 선택: HNSW 인덱싱 (문서 청크 임베딩을 적재한 후 실행)

create vector index doc_store_chunks_idx on doc_store_chunks(embed_vector)
ORGANIZATION INMEMORY NEIGHBOR GRAPH
WITH DISTANCE COSINE;
