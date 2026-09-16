# 계약 테스트: project_path_gateway_get (contracts/library-api.md 4절, FR-017, FR-020, FR-021)

. "$REPO_ROOT/lib/project-path-gateway.sh"

setup() {
	root="$TEST_TMP/root"
	make_project "$root" "${1:-APP_CONFIG=config/app.json
}"
	proot=$(physical "$root")
	project_path_gateway_init "$root" || fail_test '초기화 실패'
}

test_argument_count() {
	setup
	run_capture project_path_gateway_get
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains 'project-path-gateway: project_path_gateway_get: 인자는 KEY 1개여야 합니다'
	run_capture project_path_gateway_get A B
	assert_status 2
	assert_stdout_empty
}

test_not_initialized() {
	run_capture project_path_gateway_get APP_CONFIG
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains 'project-path-gateway: project_path_gateway_get: 초기화되지 않았습니다. project_path_gateway_init을 먼저 호출하세요'
}

test_unknown_key() {
	setup
	run_capture project_path_gateway_get NOPE
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains 'project-path-gateway: project_path_gateway_get: 등록되지 않은 키입니다: NOPE'
}

test_success_prints_absolute_path() {
	setup
	run_capture project_path_gateway_get APP_CONFIG
	assert_status 0
	assert_stdout_eq "$proot/config/app.json"
	assert_stderr_empty
}

test_path_existence_is_not_checked() {
	setup
	[ ! -e "$root/config/app.json" ] || fail_test '준비 오류'
	run_capture project_path_gateway_get APP_CONFIG
	assert_status 0
}

test_data_file_changes_after_init() {
	setup
	write_conf "$root" 'APP_CONFIG=config/new.json
'
	run_capture project_path_gateway_get APP_CONFIG
	assert_status 0
	assert_stdout_eq "$proot/config/new.json"

	write_conf "$root" 'bad line
'
	run_capture project_path_gateway_get APP_CONFIG
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains "$(conf_path "$proot"):1: "

	rm "$(conf_path "$root")"
	run_capture project_path_gateway_get APP_CONFIG
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains "project-path-gateway: project_path_gateway_get: 데이터 파일을 읽을 수 없습니다: $(conf_path "$proot")"
}

test_root_deleted_after_init() {
	setup
	rm -rf "$root"
	run_capture project_path_gateway_get APP_CONFIG
	assert_status 2
	assert_stdout_empty
}

test_paths_are_joined_verbatim() {
	setup 'SPACE=a b/c d
KOREAN=한글/경로
EQUAL=a=b
DASH=-x
DOT=./a
TRAIL=dir/
EMPTYSEG=a//b
'
	for pair in 'SPACE:a b/c d' 'KOREAN:한글/경로' 'EQUAL:a=b' 'DASH:-x' 'DOT:./a' 'TRAIL:dir/' 'EMPTYSEG:a//b'; do
		run_capture project_path_gateway_get "${pair%%:*}"
		assert_status 0
		assert_stdout_eq "$proot/${pair#*:}"
	done
}
