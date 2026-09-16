# 도메인 단위 테스트: 전역 프로그램의 파일별 처리 결정과 생성 내용 (data-model 2.2, contracts/files.md)
# 도메인 함수만 호출하며 파일 읽기와 라이브러리 호출은 하지 않는다.

PPG_SOURCE_ONLY=1
. "$REPO_ROOT/bin/project-path-gateway"

check_plan() {
	# $1: 기대 처리, $2: 종류, $3: 상태
	assert_eq "$(ppg__domain_plan_action "$2" "$3")" "$1" "종류 $2, 상태 $3"
}

test_plan_action_table() {
	check_plan create marker absent
	check_plan keep marker file
	check_plan fail marker other
	check_plan create data absent
	check_plan keep data file
	check_plan fail data other
	check_plan create library absent
	check_plan replace library file
	check_plan fail library other
}

test_marker_content_bytes() {
	printf '%s\n%s\n' \
		'# project-path-gateway 루트 표식 파일입니다. 이 파일을 담은 .tool/ 디렉터리의 상위 디렉터리가 프로젝트 루트입니다.' \
		'format=1' >"$TEST_TMP/want"
	ppg__domain_marker_content >"$TEST_TMP/got"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/got" || fail_test '루트 표식 파일 내용이 contracts/files.md 2절과 다름'
}

test_data_template_bytes() {
	printf '%s\n' \
		'# project-path-gateway 데이터 파일' \
		'# 한 줄에 KEY=경로 형식으로 적습니다. 경로는 프로젝트 루트(.tool/의 상위 디렉터리) 기준 상대경로입니다.' \
		'# 키: 대문자로 시작하고 대문자·숫자·_만 사용합니다. 파일 안에서 중복될 수 없습니다.' \
		'# 경로: /로 시작할 수 없고 .. 세그먼트를 쓸 수 없습니다. = 앞뒤 공백은 제거되지 않습니다.' \
		'# 빈 줄과 #으로 시작하는 줄은 무시합니다.' \
		'#' \
		'# 예:' \
		'# SOURCES_ROOT=sources' \
		'# BUILD_SCRIPT=scripts/build.sh' >"$TEST_TMP/want"
	ppg__domain_data_template >"$TEST_TMP/got"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/got" || fail_test '데이터 파일 내용이 contracts/files.md 3.2절과 다름'
}

test_names_and_paths() {
	assert_eq "$(ppg__domain_tool_relpath)" .tool/project-path-gateway '도구 디렉터리'
	assert_eq "$(ppg__domain_file_name marker)" .project-path-gateway '표식 파일 이름'
	assert_eq "$(ppg__domain_file_name data)" project-path-gateway.conf '데이터 파일 이름'
	assert_eq "$(ppg__domain_file_name library)" project-path-gateway.sh '라이브러리 이름'
	assert_eq "$(ppg__domain_join '/a b' .tool)" '/a b/.tool' '결합'
	assert_eq "$(ppg__domain_join / .tool)" /.tool '루트 결합'
}
