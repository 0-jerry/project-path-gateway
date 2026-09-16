# 계약 테스트: project_path_gateway_verify (contracts/library-api.md 5절, FR-030~FR-034)

. "$REPO_ROOT/lib/project-path-gateway.sh"

setup() {
	root="$TEST_TMP/root"
	make_project "$root" "$1"
	proot=$(physical "$root")
	project_path_gateway_init "$root" || fail_test '초기화 실패'
}

test_argument_is_rejected() {
	setup ''
	run_capture project_path_gateway_verify extra
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains 'project-path-gateway: project_path_gateway_verify: 인자를 받지 않습니다'
}

test_not_initialized() {
	run_capture project_path_gateway_verify
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains 'project-path-gateway: project_path_gateway_verify: 초기화되지 않았습니다. project_path_gateway_init을 먼저 호출하세요'
}

test_data_file_errors_skip_entry_checks() {
	setup 'MISSING=nope
'
	write_conf "$root" 'MISSING=nope
bad
'
	run_capture project_path_gateway_verify
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains "$(conf_path "$proot"):2: "
	assert_stderr_not_contains '누락'

	rm "$(conf_path "$root")"
	run_capture project_path_gateway_verify
	assert_status 2
	assert_stderr_contains "project-path-gateway: project_path_gateway_verify: 데이터 파일을 읽을 수 없습니다: $(conf_path "$proot")"
	assert_stderr_not_contains '누락'
}

# 시나리오 1
test_all_entries_pass() {
	setup 'A=a
B=b/c
'
	mkdir -p "$root/a" "$root/b"
	: >"$root/b/c"
	run_capture project_path_gateway_verify
	assert_status 0
	assert_stdout_eq 'project-path-gateway: 검증 통과 2건'
	assert_stderr_empty
}

test_zero_entries_pass() {
	setup '# 항목 없음
'
	run_capture project_path_gateway_verify
	assert_status 0
	assert_stdout_eq 'project-path-gateway: 검증 통과 0건'
}

# 시나리오 2
test_missing_entries_are_all_reported_in_order() {
	setup 'B=gone_b
KEEP=keep
A=gone a
'
	mkdir -p "$root/keep"
	run_capture project_path_gateway_verify
	assert_status 1
	assert_stdout_empty
	assert_stderr_lines 3
	assert_stderr_line 1 'project-path-gateway: 누락: B=gone_b'
	assert_stderr_line 2 'project-path-gateway: 누락: A=gone a'
	assert_stderr_line -1 'project-path-gateway: 검증 실패 2건'
}
