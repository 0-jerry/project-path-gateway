# 계약 테스트: 전역 프로그램 명령줄 (contracts/cli.md 1절·2절, FR-083, FR-084)

setup() {
	prefix="$TEST_TMP/prefix"
	install_to "$prefix" || fail_test '설치 실패'
	ppg="$prefix/bin/project-path-gateway"
	version=$(cat "$REPO_ROOT/VERSION")
}

test_no_arguments() {
	setup
	run_capture "$ppg"
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains '사용법'
}

test_help() {
	setup
	for option in --help -h; do
		run_capture "$ppg" "$option"
		assert_status 0
		assert_stdout_contains 'project-path-gateway init [TARGET_DIR]'
	done
}

test_version() {
	setup
	run_capture "$ppg" --version
	assert_status 0
	assert_stdout_eq "project-path-gateway $version"
}

test_unknown_commands_including_get_and_verify() {
	setup
	for command in foo --bogus get verify; do
		run_capture "$ppg" "$command" KEY
		assert_status 2
		assert_stdout_empty
		assert_stderr_contains "project-path-gateway: 알 수 없는 명령입니다: $command"
	done
}

test_init_too_many_arguments() {
	setup
	mkdir -p "$TEST_TMP/a" "$TEST_TMP/b"
	run_capture "$ppg" init "$TEST_TMP/a" "$TEST_TMP/b"
	assert_status 2
	assert_stderr_contains 'project-path-gateway: init: 인자는 0개 또는 1개여야 합니다'
	assert_not_exists "$TEST_TMP/a/.tool"
	assert_not_exists "$TEST_TMP/b/.tool"
}

test_init_target_not_directory() {
	setup
	run_capture "$ppg" init "$TEST_TMP/nope"
	assert_status 2
	assert_stderr_contains "project-path-gateway: init: 디렉터리가 아닙니다: $TEST_TMP/nope"
	assert_not_exists "$TEST_TMP/nope"
	: >"$TEST_TMP/file"
	run_capture "$ppg" init "$TEST_TMP/file"
	assert_status 2
	assert_stderr_contains "project-path-gateway: init: 디렉터리가 아닙니다: $TEST_TMP/file"
}

# 사용자 스토리 0 시나리오 11
test_init_tool_is_regular_file() {
	setup
	mkdir -p "$TEST_TMP/p"
	printf 'keep\n' >"$TEST_TMP/p/.tool"
	before=$(tree_list "$TEST_TMP/p")
	run_capture "$ppg" init "$TEST_TMP/p"
	assert_status 2
	assert_stdout_empty
	assert_stderr_contains 'project-path-gateway: init: .tool이 디렉터리가 아닙니다: '
	assert_eq "$(cat "$TEST_TMP/p/.tool")" keep '.tool 내용'
	assert_eq "$(tree_list "$TEST_TMP/p")" "$before" '항목 목록'
}

test_init_tool_directory_is_regular_file() {
	setup
	mkdir -p "$TEST_TMP/p/.tool"
	: >"$TEST_TMP/p/.tool/project-path-gateway"
	run_capture "$ppg" init "$TEST_TMP/p"
	assert_status 2
	assert_stderr_contains 'project-path-gateway: init: 도구 디렉터리가 디렉터리가 아닙니다: '
}

test_init_tool_file_is_directory() {
	setup
	for name in .project-path-gateway project-path-gateway.conf project-path-gateway.sh; do
		project="$TEST_TMP/p-$name"
		mkdir -p "$project/.tool/project-path-gateway/$name"
		before=$(tree_list "$project")
		run_capture "$ppg" init "$project"
		assert_status 2
		assert_stdout_empty
		assert_stderr_contains "project-path-gateway: init: 일반 파일이 아닙니다: "
		assert_stderr_contains "$name"
		assert_eq "$(tree_list "$project")" "$before" "$name 사전 검사 후 변경 없음"
	done
}

test_init_output_format() {
	setup
	mkdir -p "$TEST_TMP/p"
	run_capture "$ppg" init "$TEST_TMP/p"
	assert_status 0
	assert_stderr_empty
	printf '%s\n' \
		'project-path-gateway: 생성: .tool/project-path-gateway/.project-path-gateway' \
		'project-path-gateway: 생성: .tool/project-path-gateway/project-path-gateway.conf' \
		'project-path-gateway: 생성: .tool/project-path-gateway/project-path-gateway.sh' \
		"project-path-gateway: 초기화 완료: $(physical "$TEST_TMP/p")" >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/stdout" || fail_test '출력 형식이 다름'

	run_capture "$ppg" init "$TEST_TMP/p"
	assert_status 0
	printf '%s\n' \
		'project-path-gateway: 유지: .tool/project-path-gateway/.project-path-gateway' \
		'project-path-gateway: 유지: .tool/project-path-gateway/project-path-gateway.conf' \
		'project-path-gateway: 교체: .tool/project-path-gateway/project-path-gateway.sh' \
		"project-path-gateway: 초기화 완료: $(physical "$TEST_TMP/p")" >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/stdout" || fail_test '재실행 출력 형식이 다름'
}
