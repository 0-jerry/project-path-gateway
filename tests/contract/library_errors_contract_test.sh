# 계약 테스트: 잘못된 인자·루트·데이터 파일을 초기화 시점에 거부 (사용자 스토리 3, contracts/library-api.md 3절·6절)

. "$REPO_ROOT/lib/project-path-gateway.sh"

setup() {
	root="$TEST_TMP/root"
	make_project "$root" "$1"
	proot=$(physical "$root")
	conf=$(conf_path "$proot")
}

expect_init_failure() {
	run_here project_path_gateway_init "$@"
	assert_status 2
	assert_stdout_empty
	[ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ] || fail_test '미초기화여야 함'
}

# 시나리오 1
test_invalid_arguments() {
	setup ''
	: >"$TEST_TMP/regular"
	expect_init_failure "$root" "$root"
	assert_stderr_contains 'project-path-gateway: project_path_gateway_init: 인자는 0개 또는 1개여야 합니다'
	expect_init_failure relative/path
	assert_stderr_contains 'project-path-gateway: project_path_gateway_init: 절대경로가 아닙니다: relative/path'
	expect_init_failure "$TEST_TMP/nope"
	assert_stderr_contains "project-path-gateway: project_path_gateway_init: 디렉터리가 아닙니다: $TEST_TMP/nope"
	expect_init_failure "$TEST_TMP/regular"
	assert_stderr_contains "project-path-gateway: project_path_gateway_init: 디렉터리가 아닙니다: $TEST_TMP/regular"
}

# 시나리오 2
test_marker_without_data_file() {
	setup ''
	rm "$(conf_path "$root")"
	expect_init_failure "$root"
	assert_stderr_contains "데이터 파일을 읽을 수 없습니다: $conf"
}

# 시나리오 3
test_absolute_path_on_line_four() {
	setup '# 1
A=a

BAD=/etc/hosts
'
	expect_init_failure "$root"
	assert_stderr_lines 1
	assert_stderr_line 1 "project-path-gateway: $conf:4: 경로는 /로 시작할 수 없습니다: BAD"
}

check_violation() {
	# $1: 2번째 줄 내용, $2: 원인 문구에 포함될 어구, $3: 포함될 키(없으면 빈 문자열)
	write_conf "$root" "# 첫 줄은 주석
$1
"
	expect_init_failure "$root"
	assert_stderr_lines 1
	assert_stderr_line_contains 1 "project-path-gateway: $conf:2: $2"
	if [ -n "$3" ]; then
		assert_stderr_line_contains 1 ": $3"
	fi
}

# 시나리오 4
test_each_violation_reports_line_and_cause() {
	setup ''
	cr=$(printf '\r')
	check_violation 'no separator' 'KEY=경로 형식이 아닙니다' ''
	check_violation 'app=x' '키 형식이 잘못되었습니다' app
	check_violation 'E=' '경로가 비어 있습니다' E
	check_violation 'P=..' '경로에 .. 세그먼트를 쓸 수 없습니다' P
	check_violation 'P=a/..' '경로에 .. 세그먼트를 쓸 수 없습니다' P
	check_violation 'P=a/../b' '경로에 .. 세그먼트를 쓸 수 없습니다' P
	check_violation "C=x$cr" 'CR 문자가 포함되어 있습니다' ''
	check_violation '   ' 'KEY=경로 형식이 아닙니다' ''
	check_violation ' #comment' 'KEY=경로 형식이 아닙니다' ''

	write_conf "$root" 'A=1
B=2
A=3
'
	expect_init_failure "$root"
	assert_stderr_lines 1
	assert_stderr_line 1 "project-path-gateway: $conf:3: 중복된 키입니다(1번째 줄에서 정의됨): A"
}

# 시나리오 5
test_all_violations_in_file_order() {
	setup 'lower=a
OK=fine
X=/abs

Y=
'
	expect_init_failure "$root"
	assert_stderr_lines 3
	assert_stderr_line_contains 1 "$conf:1: "
	assert_stderr_line_contains 2 "$conf:3: "
	assert_stderr_line_contains 3 "$conf:5: "
}

# 시나리오 6
test_failed_reinit_leaves_uninitialized() {
	setup 'A=a
'
	run_here project_path_gateway_init "$root"
	assert_status 0
	run_here project_path_gateway_init relative
	assert_status 2
	run_capture project_path_gateway_get A
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains '초기화되지 않았습니다'
}

# 시나리오 7
test_no_marker_up_to_filesystem_root() {
	mkdir -p "$TEST_TMP/plain/sub"
	expect_init_failure "$TEST_TMP/plain/sub"
	assert_stderr_contains "루트 표식 파일(.tool/project-path-gateway/.project-path-gateway)을 찾지 못했습니다: $(physical "$TEST_TMP/plain/sub")부터 /까지"
}

# 경계 사례: CRLF 줄 끝 데이터 파일
test_crlf_file_mentions_crlf_on_every_reported_line() {
	cr=$(printf '\r')
	setup "# 주석$cr
$cr
A=a$cr
b=c$cr
"
	expect_init_failure "$root"
	assert_stderr_lines 3
	assert_stderr_line_contains 1 "$conf:2: KEY=경로 형식이 아닙니다"
	assert_stderr_line_contains 2 "$conf:3: CR 문자가 포함되어 있습니다"
	assert_stderr_line_contains 3 "$conf:4: 키 형식이 잘못되었습니다"
	for n in 1 2 3; do
		assert_stderr_line_contains "$n" 'CRLF 줄 끝인지 확인하세요'
	done
}
