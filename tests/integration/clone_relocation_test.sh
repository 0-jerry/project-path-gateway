# 통합 테스트: clone·이동한 프로젝트가 전역 프로그램 없이 새 위치 기준으로 동작 (사용자 스토리 0 시나리오 2·3, FR-082)

setup_project() {
	prefix="$TEST_TMP/prefix"
	install_to "$prefix" || fail_test '설치 실패'
	project="$TEST_TMP/origin"
	mkdir -p "$project/config"
	: >"$project/config/app.json"
	"$prefix/bin/project-path-gateway" init "$project" >/dev/null || fail_test '초기화 실패'
	printf 'APP_CONFIG=config/app.json\n' >>"$(conf_path "$project")"
}

check_location() {
	run_capture in_shell 'cd "$1" && . ./.tool/project-path-gateway/project-path-gateway.sh && project_path_gateway_init && project_path_gateway_get APP_CONFIG && project_path_gateway_verify' _ "$1"
	assert_status 0
	assert_stdout_contains "$(physical "$1")/config/app.json"
	assert_stdout_contains '검증 통과 1건'
}

# 시나리오 2
test_clone_to_other_path_without_global_program() {
	setup_project
	if command -v git >/dev/null 2>&1; then
		if ! git -C "$project" init -q ||
			! git -C "$project" add -A ||
			! git -C "$project" -c user.name=tester -c user.email=tester@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init; then
			fail_test 'git 준비 실패'
		fi
		git clone -q "$project" "$TEST_TMP/clone/복제 위치" || fail_test 'clone 실패'
	else
		mkdir -p "$TEST_TMP/clone"
		cp -R "$project" "$TEST_TMP/clone/복제 위치"
	fi
	sh "$REPO_ROOT/uninstall.sh" --prefix "$prefix" >/dev/null || fail_test '제거 실패'
	check_location "$TEST_TMP/clone/복제 위치"
}

# 시나리오 3
test_moved_project_needs_no_reinit() {
	setup_project
	mv "$project" "$TEST_TMP/moved"
	check_location "$TEST_TMP/moved"
}
