# 통합 테스트: 설치·제거 스크립트 (contracts/install.md, FR-088~FR-090, SC-008, SC-009)

copy_repo() {
	repo="$TEST_TMP/repo"
	mkdir -p "$repo"
	cp -R "$REPO_ROOT/bin" "$REPO_ROOT/lib" "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT/VERSION" "$repo/"
}

test_default_prefix_uses_home() {
	copy_repo
	mkdir -p "$TEST_TMP/home"
	HOME="$TEST_TMP/home" run_capture sh "$repo/install.sh"
	assert_status 0
	assert_file_exists "$TEST_TMP/home/.local/bin/project-path-gateway"
	assert_stdout_contains "project-path-gateway: 설치 완료: $TEST_TMP/home/.local (버전 $(cat "$REPO_ROOT/VERSION"))"
}

test_prefix_option_and_files() {
	copy_repo
	prefix="$TEST_TMP/prefix"
	run_capture sh "$repo/install.sh" --prefix "$prefix"
	assert_status 0
	assert_eq "$(mode_of "$prefix/bin/project-path-gateway")" '-rwxr-xr-x' '실행 파일 권한'
	for f in project-path-gateway.sh VERSION install-manifest; do
		assert_eq "$(mode_of "$prefix/share/project-path-gateway/$f")" '-rw-r--r--' "$f 권한"
	done
	printf '%s\n' bin/project-path-gateway share/project-path-gateway/project-path-gateway.sh \
		share/project-path-gateway/VERSION share/project-path-gateway/install-manifest >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$prefix/share/project-path-gateway/install-manifest" || fail_test '설치 목록 내용'
	cmp -s "$REPO_ROOT/lib/project-path-gateway.sh" "$prefix/share/project-path-gateway/project-path-gateway.sh" || fail_test '라이브러리 원본'
}

test_prefix_option_overrides_environment() {
	copy_repo
	PREFIX="$TEST_TMP/env" run_capture sh "$repo/install.sh" --prefix "$TEST_TMP/opt"
	assert_status 0
	assert_file_exists "$TEST_TMP/opt/bin/project-path-gateway"
	assert_not_exists "$TEST_TMP/env"
	PREFIX="$TEST_TMP/env" run_capture sh "$repo/install.sh"
	assert_status 0
	assert_file_exists "$TEST_TMP/env/bin/project-path-gateway"
}

test_path_guidance() {
	copy_repo
	prefix="$TEST_TMP/prefix"
	PATH="/usr/bin:/bin" run_capture sh "$repo/install.sh" --prefix "$prefix"
	assert_status 0
	assert_stdout_contains "export PATH=\"$prefix/bin:\$PATH\""
	PATH="$prefix/bin:/usr/bin:/bin" run_capture sh "$repo/install.sh" --prefix "$prefix"
	assert_status 0
	if grep -F 'export PATH' "$TEST_TMP/stdout" >/dev/null; then
		fail_test 'PATH에 있으면 안내하지 않아야 함'
	fi
}

test_reinstall_replaces_files() {
	copy_repo
	prefix="$TEST_TMP/prefix"
	sh "$repo/install.sh" --prefix "$prefix" >/dev/null || fail_test '설치 실패'
	printf 'old\n' >"$prefix/share/project-path-gateway/project-path-gateway.sh"
	run_capture sh "$repo/install.sh" --prefix "$prefix"
	assert_status 0
	cmp -s "$repo/lib/project-path-gateway.sh" "$prefix/share/project-path-gateway/project-path-gateway.sh" || fail_test '교체되지 않음'
}

test_runs_from_other_working_directory() {
	copy_repo
	mkdir -p "$TEST_TMP/elsewhere"
	cd "$TEST_TMP/elsewhere" || fail_test cd
	run_capture sh ../repo/install.sh --prefix "$TEST_TMP/prefix"
	assert_status 0
	assert_file_exists "$TEST_TMP/prefix/share/project-path-gateway/VERSION"
	assert_eq "$(dir_entries "$TEST_TMP/elsewhere")" '' '작업 디렉터리 변경 없음'
}

test_invalid_arguments() {
	copy_repo
	run_capture sh "$repo/install.sh" --bogus
	assert_status 2
	assert_stderr_contains '사용법'
	run_capture sh "$repo/install.sh" --prefix
	assert_status 2
	run_capture sh "$repo/uninstall.sh" --bogus
	assert_status 2
}

test_install_write_failure() {
	[ "$(id -u)" != 0 ] || skip_test 'root 사용자는 권한 제한이 적용되지 않음'
	copy_repo
	mkdir -p "$TEST_TMP/locked"
	chmod 555 "$TEST_TMP/locked"
	run_capture sh "$repo/install.sh" --prefix "$TEST_TMP/locked/prefix"
	chmod 755 "$TEST_TMP/locked"
	assert_status 1
	assert_stderr_contains 'project-path-gateway: 설치 실패: '
}

test_uninstall_removes_installed_files_only() {
	copy_repo
	prefix="$TEST_TMP/prefix"
	mkdir -p "$prefix/bin"
	: >"$prefix/bin/other-tool"
	sh "$repo/install.sh" --prefix "$prefix" >/dev/null || fail_test '설치 실패'
	run_capture sh "$repo/uninstall.sh" --prefix "$prefix"
	assert_status 0
	assert_stdout_contains "project-path-gateway: 제거 완료: $prefix"
	assert_not_exists "$prefix/bin/project-path-gateway"
	assert_not_exists "$prefix/share/project-path-gateway"
	assert_file_exists "$prefix/bin/other-tool"
	[ -d "$prefix/bin" ] || fail_test '<PREFIX>/bin은 남아야 함'
}

test_uninstall_skips_already_missing_file() {
	copy_repo
	prefix="$TEST_TMP/prefix"
	sh "$repo/install.sh" --prefix "$prefix" >/dev/null || fail_test '설치 실패'
	rm "$prefix/bin/project-path-gateway"
	run_capture sh "$repo/uninstall.sh" --prefix "$prefix"
	assert_status 0
	assert_not_exists "$prefix/share/project-path-gateway"
}

test_uninstall_without_manifest() {
	copy_repo
	mkdir -p "$TEST_TMP/empty"
	run_capture sh "$repo/uninstall.sh" --prefix "$TEST_TMP/empty"
	assert_status 1
	assert_stderr_contains "project-path-gateway: 설치 기록이 없습니다: $TEST_TMP/empty"
}

test_uninstall_rejects_unsafe_manifest() {
	copy_repo
	prefix="$TEST_TMP/prefix"
	sh "$repo/install.sh" --prefix "$prefix" >/dev/null || fail_test '설치 실패'
	: >"$TEST_TMP/victim"
	printf '../victim\n' >>"$prefix/share/project-path-gateway/install-manifest"
	run_capture sh "$repo/uninstall.sh" --prefix "$prefix"
	assert_status 1
	assert_file_exists "$TEST_TMP/victim"
	assert_file_exists "$prefix/bin/project-path-gateway"
	printf '/abs\n' >"$prefix/share/project-path-gateway/install-manifest"
	run_capture sh "$repo/uninstall.sh" --prefix "$prefix"
	assert_status 1
	assert_file_exists "$prefix/bin/project-path-gateway"
}

# SC-009
test_initialized_project_works_after_uninstall() {
	copy_repo
	prefix="$TEST_TMP/prefix"
	sh "$repo/install.sh" --prefix "$prefix" >/dev/null || fail_test '설치 실패'
	project="$TEST_TMP/project"
	mkdir -p "$project/config"
	: >"$project/config/app.json"
	"$prefix/bin/project-path-gateway" init "$project" >/dev/null || fail_test '초기화 실패'
	printf 'APP_CONFIG=config/app.json\n' >>"$(conf_path "$project")"
	sh "$repo/uninstall.sh" --prefix "$prefix" >/dev/null || fail_test '제거 실패'
	assert_not_exists "$prefix/share/project-path-gateway"
	run_capture in_shell '. "$1"; project_path_gateway_init "$2" && project_path_gateway_get APP_CONFIG && project_path_gateway_verify' _ "$(lib_path "$project")" "$project"
	assert_status 0
	assert_stdout_contains "$(physical "$project")/config/app.json"
	assert_stdout_contains '검증 통과 1건'
}

# SC-008: 저장소 받기, 설치 스크립트, 첫 프로젝트 초기화까지 명령 3개
test_three_commands_to_first_init() {
	mkdir -p "$TEST_TMP/project"
	cd "$TEST_TMP/project" || fail_test cd
	prefix="$TEST_TMP/prefix"
	commands=0
	cp -R "$REPO_ROOT" "$TEST_TMP/cloned" && commands=$((commands + 1))
	sh "$TEST_TMP/cloned/install.sh" --prefix "$prefix" >/dev/null && commands=$((commands + 1))
	"$prefix/bin/project-path-gateway" init >/dev/null && commands=$((commands + 1))
	assert_eq "$commands" 3 '성공한 명령 수'
	assert_file_exists "$(lib_path "$TEST_TMP/project")"
}
