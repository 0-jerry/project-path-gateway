# 통합 테스트: 데이터 파일 읽기와 검증 흐름 (FR-011~FR-017)

. "$REPO_ROOT/lib/project-path-gateway.sh"

setup_root() {
	root="$TEST_TMP/root"
	make_project "$root" "$1"
}

test_valid_file_records() {
	setup_root 'A=a
# 주석

B=b c
'
	run_capture project_path_gateway__app_load_entries "$root"
	assert_status 0
	assert_stderr_empty
	printf '1\tA\ta\n4\tB\tb c\n' >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/stdout" || fail_test "레코드가 다름"
}

test_last_line_without_newline() {
	setup_root 'A=a
B=b'
	run_capture project_path_gateway__app_load_entries "$root"
	assert_status 0
	printf '1\tA\ta\n2\tB\tb\n' >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/stdout" || fail_test "마지막 줄 누락"
}

test_all_violations_reported_in_order() {
	setup_root 'a=b
OK=x
B
=c
'
	run_capture project_path_gateway__app_load_entries "$root"
	assert_status 3
	assert_stderr_lines 3
	conf=$(conf_path "$root")
	assert_stderr_line_contains 1 "project-path-gateway: $conf:1: "
	assert_stderr_line_contains 2 "project-path-gateway: $conf:3: "
	assert_stderr_line_contains 3 "project-path-gateway: $conf:4: "
}

test_duplicate_key_reports_first_line() {
	setup_root 'A=1
B=2
A=3
'
	run_capture project_path_gateway__app_load_entries "$root"
	assert_status 3
	assert_stderr_lines 1
	assert_stderr_line_contains 1 ":3: "
	assert_stderr_line_contains 1 "1번째 줄"
	assert_stderr_line_contains 1 ": A"
}

test_missing_file() {
	setup_root ''
	rm "$(conf_path "$root")"
	run_capture project_path_gateway__app_load_entries "$root"
	assert_status 4
	assert_stdout_empty
}

test_zero_entries() {
	setup_root '# 항목 없음
'
	run_capture project_path_gateway__app_load_entries "$root"
	assert_status 0
	assert_stdout_empty
	assert_stderr_empty
}

test_path_keeps_tab_equal_and_korean() {
	setup_root 'A=x	y=z/한글
'
	run_capture project_path_gateway__app_load_entries "$root"
	assert_status 0
	printf '1\tA\tx\ty=z/한글\n' >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/stdout" || fail_test "경로 원문이 바뀜"
}
