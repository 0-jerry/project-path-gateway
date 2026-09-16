# 통합 테스트: README의 세 사용 예가 수정 없이 동작 (SC-005, FR-070, FR-071)
# 전역 프로그램으로 초기화하고 항목만 등록한 새 프로젝트에서 README 코드 블록을 그대로 실행한다.

# README에서 <!-- example: NAME --> 표지 뒤 첫 ```sh 코드 블록을 출력한다.
extract_example() {
	awk -v marker="<!-- example: $1 -->" '
		$0 == marker { found = 1; next }
		found == 1 && /^```sh$/ { found = 2; next }
		found == 2 && /^```$/ { exit }
		found == 2 { print }
	' "$REPO_ROOT/README.md"
}

setup_project() {
	prefix="$TEST_TMP/prefix"
	install_to "$prefix" || fail_test '설치 실패'
	project="$TEST_TMP/my project"
	mkdir -p "$project/config"
	: >"$project/config/app.json"
	"$prefix/bin/project-path-gateway" init "$project" >/dev/null || fail_test '초기화 실패'
	printf 'APP_CONFIG=config/app.json\n' >>"$(conf_path "$project")"
	pproject=$(physical "$project")
}

test_readme_has_all_examples() {
	for name in in-project outside-project pre-commit; do
		[ -n "$(extract_example "$name")" ] || fail_test "README 사용 예 없음: $name"
	done
}

test_in_project_example() {
	setup_project
	mkdir -p "$project/scripts"
	extract_example in-project >"$project/scripts/show-config.sh"
	cd "$project" || fail_test cd
	run_capture "$TEST_SHELL" scripts/show-config.sh
	assert_status 0
	assert_stdout_eq "설정 파일: $pproject/config/app.json"
}

test_outside_project_example() {
	setup_project
	mkdir -p "$TEST_TMP/elsewhere"
	extract_example outside-project >"$TEST_TMP/elsewhere/deploy.sh"
	cd "$TEST_TMP/elsewhere" || fail_test cd
	run_capture "$TEST_SHELL" deploy.sh "$project"
	assert_status 0
	assert_stdout_eq "$pproject/config/app.json"
}

test_pre_commit_example() {
	command -v git >/dev/null 2>&1 || skip_test 'git이 없음'
	setup_project
	git init -q "$project" || fail_test 'git init 실패'
	extract_example pre-commit >"$project/.git/hooks/pre-commit"
	chmod 755 "$project/.git/hooks/pre-commit"
	git_project() {
		git -C "$project" -c core.hooksPath=.git/hooks -c commit.gpgsign=false \
			-c user.name=tester -c user.email=tester@example.invalid "$@"
	}
	git_project add -A
	run_capture git_project commit -q -m init
	assert_status 0
	# git은 훅의 stdout을 stderr로 전달한다
	assert_stderr_contains '검증 통과 1건'
	count=$(git_project rev-list --count HEAD)
	rm "$project/config/app.json"
	run_capture git_project commit -q -a -m '경로 삭제'
	[ "$CAPTURED_STATUS" -ne 0 ] || fail_test '커밋이 중단되어야 함'
	assert_stderr_contains '누락: APP_CONFIG=config/app.json'
	assert_eq "$(git_project rev-list --count HEAD)" "$count" '커밋 수'
}
