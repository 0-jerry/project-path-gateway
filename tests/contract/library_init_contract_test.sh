# 계약 테스트: project_path_gateway_init (contracts/library-api.md 3절, FR-002~FR-006)

. "$REPO_ROOT/lib/project-path-gateway.sh"

setup() {
	root="$TEST_TMP/root"
	make_project "$root" 'APP_CONFIG=config/app.json
'
	proot=$(physical "$root")
}

test_init_without_argument_at_root() {
	setup
	cd "$root" || fail_test cd
	run_here project_path_gateway_init
	assert_status 0
	assert_stdout_empty
	assert_stderr_empty
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$proot" '루트'
}

test_init_with_absolute_argument() {
	setup
	cd / || fail_test cd
	run_here project_path_gateway_init "$root"
	assert_status 0
	assert_stdout_empty
	assert_stderr_empty
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$proot" '루트'
}

test_init_fails_without_marker() {
	mkdir -p "$TEST_TMP/plain"
	run_here project_path_gateway_init "$TEST_TMP/plain"
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains 'project-path-gateway: project_path_gateway_init: 루트 표식 파일(.tool/project-path-gateway/.project-path-gateway)을 찾지 못했습니다: '
	assert_stderr_contains "$(physical "$TEST_TMP/plain")부터 /까지"
	[ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ] || fail_test '미초기화여야 함'
}

test_init_fails_without_data_file() {
	setup
	rm "$(conf_path "$root")"
	run_here project_path_gateway_init "$root"
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains "project-path-gateway: project_path_gateway_init: 데이터 파일을 읽을 수 없습니다: $(conf_path "$proot")"
}

test_init_fails_for_non_directory_argument() {
	setup
	run_here project_path_gateway_init "$TEST_TMP/nope"
	assert_status 2
	assert_stderr_contains "project-path-gateway: project_path_gateway_init: 디렉터리가 아닙니다: $TEST_TMP/nope"
}

test_init_keeps_working_directory() {
	setup
	mkdir -p "$root/a"
	cd "$root/a" || fail_test cd
	before=$(pwd)
	run_here project_path_gateway_init
	assert_status 0
	assert_eq "$(pwd)" "$before" '작업 디렉터리 (성공)'
	run_here project_path_gateway_init "$TEST_TMP/nope"
	assert_eq "$(pwd)" "$before" '작업 디렉터리 (실패)'
}

test_failed_init_unsets_previous_root() {
	setup
	run_here project_path_gateway_init "$root"
	assert_status 0
	run_here project_path_gateway_init "$TEST_TMP/nope"
	assert_status 2
	[ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ] || fail_test '이전 루트가 남아 있음'
}

test_successful_reinit_replaces_root() {
	setup
	make_project "$TEST_TMP/other" ''
	run_here project_path_gateway_init "$root"
	run_here project_path_gateway_init "$TEST_TMP/other"
	assert_status 0
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$(physical "$TEST_TMP/other")" '새 루트'
}

# FR-003, 경계 사례 "스크립트 실행이 끝남"
test_root_is_not_kept_outside_execution() {
	setup
	time_ref "$TEST_TMP/ref"
	before=$(tree_list "$root")
	run_here project_path_gateway_init "$root"
	assert_status 0
	if export -p | grep -F PROJECT_PATH_GATEWAY_ROOT >/dev/null; then
		fail_test 'export되어 있음'
	fi
	child=$(in_shell 'printf %s "${PROJECT_PATH_GATEWAY_ROOT+set}"')
	assert_eq "$child" '' '자식 프로세스에서 보임'
	run_here in_shell '. "$1"; project_path_gateway_get APP_CONFIG' _ "$(lib_path "$root")"
	assert_status 2
	assert_stderr_contains '초기화되지 않았습니다'
	assert_eq "$(tree_list "$root")" "$before" '루트 아래 항목 목록'
	assert_eq "$(changed_since "$TEST_TMP/ref" "$root")" '' '루트 아래 변경'
}
