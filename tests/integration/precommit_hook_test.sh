# 통합 테스트: pre-commit 훅에서 검증 실패 시 커밋 중단 (사용자 스토리 2 시나리오 5, SC-007)

git_repo() {
	git -C "$repo" -c core.hooksPath=.git/hooks -c commit.gpgsign=false \
		-c user.name=tester -c user.email=tester@example.invalid "$@"
}

test_hook_blocks_commit_when_path_missing() {
	command -v git >/dev/null 2>&1 || skip_test 'git이 없음'
	repo="$TEST_TMP/repo"
	mkdir -p "$repo/config"
	git init -q "$repo" || fail_test 'git init 실패'
	make_project "$repo" 'APP_CONFIG=config/app.json
'
	: >"$repo/config/app.json"
	printf '%s\n' '#!/bin/sh' 'set -eu' '. ./.tool/project-path-gateway/project-path-gateway.sh' 'project_path_gateway_init' 'project_path_gateway_verify' >"$repo/.git/hooks/pre-commit"
	chmod 755 "$repo/.git/hooks/pre-commit"

	git_repo add -A
	run_capture git_repo commit -q -m init
	assert_status 0
	count=$(git_repo rev-list --count HEAD)

	rm "$repo/config/app.json"
	run_capture git_repo commit -q -a -m '경로 삭제'
	[ "$CAPTURED_STATUS" -ne 0 ] || fail_test '커밋이 중단되어야 함'
	assert_stderr_contains 'project-path-gateway: 누락: APP_CONFIG=config/app.json'
	assert_stderr_contains 'project-path-gateway: 검증 실패 1건'
	assert_eq "$(git_repo rev-list --count HEAD)" "$count" '커밋 수'
}
