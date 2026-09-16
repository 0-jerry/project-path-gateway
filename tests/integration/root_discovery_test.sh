# 통합 테스트: 루트 표식 파일 탐색 (사용자 스토리 1, FR-002, FR-007, research R-06)

. "$REPO_ROOT/lib/project-path-gateway.sh"

setup() {
	root="$TEST_TMP/${1:-root}"
	make_project "$root" 'APP_CONFIG=config/app.json
'
	proot=$(physical "$root")
}

expect_get() {
	run_capture project_path_gateway_get APP_CONFIG
	assert_status 0
	assert_stdout_eq "$1/config/app.json"
}

# 시나리오 2
test_working_directory_change_after_init() {
	setup
	cd "$root" || fail_test cd
	project_path_gateway_init || fail_test init
	cd "$TEST_TMP" || fail_test cd
	expect_get "$proot"
}

# 시나리오 3
test_symlink_start_uses_physical_root() {
	setup
	ln -s "$root" "$TEST_TMP/link"
	project_path_gateway_init "$TEST_TMP/link" || fail_test init
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$proot" '물리 경로'
	expect_get "$proot"
}

# 시나리오 6: Git 저장소가 아닌 디렉터리
test_non_git_directory() {
	setup
	[ ! -e "$root/.git" ] || fail_test '준비 오류'
	cd "$root" || fail_test cd
	project_path_gateway_init || fail_test init
	expect_get "$proot"
}

# 시나리오 7
test_nested_working_directory() {
	setup
	mkdir -p "$root/a/b"
	cd "$root/a/b" || fail_test cd
	project_path_gateway_init || fail_test init
	expect_get "$proot"
}

# 시나리오 8
test_outside_working_directory_with_argument() {
	setup
	mkdir -p "$root/a"
	cd "$TEST_TMP" || fail_test cd
	project_path_gateway_init "$root/a" || fail_test init
	expect_get "$proot"
}

# 시나리오 9
test_nearest_nested_project_wins() {
	setup
	make_project "$root/sub" 'APP_CONFIG=config/app.json
'
	mkdir -p "$root/sub/x"
	cd "$root/sub/x" || fail_test cd
	project_path_gateway_init || fail_test init
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$proot/sub" '가까운 루트'
}

# 시나리오 10
test_root_is_not_recalculated() {
	setup
	cd "$root" || fail_test cd
	project_path_gateway_init || fail_test init
	make_project "$TEST_TMP/elsewhere" 'APP_CONFIG=other
'
	cd "$TEST_TMP/elsewhere" || fail_test cd
	expect_get "$proot"
}

# 시나리오 11
test_init_inside_tool_directory() {
	setup
	cd "$root/.tool/project-path-gateway" || fail_test cd
	project_path_gateway_init || fail_test init
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$proot" '루트'
}

# 경계 사례: 루트 경로에 공백·한글 포함
test_root_with_space_and_korean() {
	setup '내 프로젝트 폴더'
	mkdir -p "$root/하위 디렉터리"
	cd "$root/하위 디렉터리" || fail_test cd
	project_path_gateway_init || fail_test init
	expect_get "$proot"
}

# 경계 사례: .tool/project-path-gateway/는 있지만 표식 없음
test_tool_directory_without_marker_is_skipped() {
	setup
	mkdir -p "$root/child/.tool/project-path-gateway"
	cd "$root/child" || fail_test cd
	project_path_gateway_init || fail_test init
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$proot" '상위 탐색 계속'
}

# 경계 사례: 표식 이름이 디렉터리
test_marker_directory_is_not_accepted() {
	setup
	mkdir -p "$root/child/.tool/project-path-gateway/.project-path-gateway"
	cd "$root/child" || fail_test cd
	project_path_gateway_init || fail_test init
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$proot" '상위 탐색 계속'
}

# 경계 사례: 표식 파일을 읽을 수 없음
test_unreadable_marker_is_accepted() {
	[ "$(id -u)" != 0 ] || skip_test 'root 사용자는 권한 제한이 적용되지 않음'
	setup
	chmod 000 "$root/.tool/project-path-gateway/.project-path-gateway"
	cd "$root" || fail_test cd
	project_path_gateway_init || fail_test init
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$proot" '루트로 인정'
}

# 이름이 개행으로 끝나는 루트 디렉터리 (research R-03)
test_root_name_ending_with_newline() {
	nl='
'
	setup "nl$nl"
	cd "$root" || fail_test cd
	project_path_gateway_init || fail_test init
	assert_eq "$PROJECT_PATH_GATEWAY_ROOT" "$(physical "$TEST_TMP")/nl$nl" '끝 개행 유지'
}
