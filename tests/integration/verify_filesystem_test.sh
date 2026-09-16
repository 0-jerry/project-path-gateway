# 통합 테스트: 검증의 존재 판정(V-1)과 루트 내부 판정(V-2) (FR-031~FR-035, research R-05)

. "$REPO_ROOT/lib/project-path-gateway.sh"

setup() {
	root="$TEST_TMP/root"
	make_project "$root" "$1"
	project_path_gateway_init "$root" || fail_test '초기화 실패'
}

# 시나리오 3
test_link_to_outside_directory() {
	mkdir -p "$TEST_TMP/outside"
	setup 'OUT=link
'
	ln -s "$TEST_TMP/outside" "$root/link"
	run_capture project_path_gateway_verify
	assert_status 1
	assert_stderr_line 1 "project-path-gateway: 루트 밖: OUT=link -> $(physical "$TEST_TMP/outside")"
	assert_stderr_line -1 'project-path-gateway: 검증 실패 1건'
}

test_link_to_outside_file_with_relative_target() {
	mkdir -p "$TEST_TMP/outside"
	: >"$TEST_TMP/outside/f"
	setup 'OUT=d/link
'
	mkdir -p "$root/d"
	ln -s ../../outside/f "$root/d/link"
	run_capture project_path_gateway_verify
	assert_status 1
	assert_stderr_line 1 "project-path-gateway: 루트 밖: OUT=d/link -> $(physical "$TEST_TMP/outside")/f"
}

# 시나리오 4
test_broken_link_is_missing() {
	setup 'BROKEN=link
'
	ln -s "$root/nope" "$root/link"
	run_capture project_path_gateway_verify
	assert_status 1
	assert_stderr_line 1 'project-path-gateway: 누락: BROKEN=link'
}

test_cyclic_link_is_missing() {
	setup 'LOOP=a
'
	ln -s b "$root/a"
	ln -s a "$root/b"
	run_capture project_path_gateway_verify
	assert_status 1
	assert_stderr_line 1 'project-path-gateway: 누락: LOOP=a'
}

test_permission_denied_is_missing() {
	[ "$(id -u)" != 0 ] || skip_test 'root 사용자는 권한 제한이 적용되지 않음'
	setup 'LOCKED=locked/file
'
	mkdir -p "$root/locked"
	: >"$root/locked/file"
	chmod 000 "$root/locked"
	run_capture project_path_gateway_verify
	chmod 755 "$root/locked"
	assert_status 1
	assert_stderr_line 1 'project-path-gateway: 누락: LOCKED=locked/file'
}

# 경계 사례: /a/root2 경로와 루트 /a/root
test_sibling_with_root_prefix_is_outside() {
	mkdir -p "$TEST_TMP/root2/x"
	setup 'SIB=sib
'
	ln -s "$TEST_TMP/root2/x" "$root/sib"
	run_capture project_path_gateway_verify
	assert_status 1
	assert_stderr_line 1 "project-path-gateway: 루트 밖: SIB=sib -> $(physical "$TEST_TMP/root2")/x"
}

test_file_link_chain_inside_root_passes() {
	setup 'CHAIN=l1
'
	mkdir -p "$root/real"
	: >"$root/real/target"
	ln -s real/target "$root/l3"
	ln -s l3 "$root/l2"
	ln -s "$root/l2" "$root/l1"
	run_capture project_path_gateway_verify
	assert_status 0
	assert_stdout_eq 'project-path-gateway: 검증 통과 1건'
}

test_directory_link_and_trailing_slash_inside_root_pass() {
	setup 'DIRLINK=dl
TRAIL=dir/
DOT=./dir/./f
'
	mkdir -p "$root/dir"
	: >"$root/dir/f"
	ln -s dir "$root/dl"
	run_capture project_path_gateway_verify
	assert_status 0
	assert_stdout_eq 'project-path-gateway: 검증 통과 3건'
}

test_missing_entry_is_not_checked_for_outside() {
	setup 'BROKEN_OUT=link
'
	ln -s /nonexistent/ppg/target "$root/link"
	run_capture project_path_gateway_verify
	assert_status 1
	assert_stderr_lines 2
	assert_stderr_line 1 'project-path-gateway: 누락: BROKEN_OUT=link'
	assert_stderr_not_contains '루트 밖'
}

test_paths_with_space_and_korean() {
	setup 'SPACE=a b/한글 파일
'
	mkdir -p "$root/a b"
	: >"$root/a b/한글 파일"
	run_capture project_path_gateway_verify
	assert_status 0
}

# 시나리오 6
test_verify_does_not_change_filesystem() {
	setup 'A=a
MISSING=nope
'
	mkdir -p "$root/a"
	time_ref "$TEST_TMP/ref"
	before=$(tree_list "$root")
	run_capture project_path_gateway_verify
	assert_status 1
	run_capture project_path_gateway_verify
	assert_eq "$(tree_list "$root")" "$before" '항목 목록'
	assert_eq "$(changed_since "$TEST_TMP/ref" "$root")" '' '변경된 항목'
}

# research R-15: 항목 200개 검증 시간 (2초 초과 시 경고만)
test_two_hundred_entries_timing() {
	root="$TEST_TMP/root"
	make_project "$root" ''
	i=0
	while [ "$i" -lt 200 ]; do
		printf 'KEY_%s=dir/file_%s\n' "$i" "$i"
		i=$((i + 1))
	done >"$(conf_path "$root")"
	mkdir -p "$root/dir"
	i=0
	while [ "$i" -lt 200 ]; do
		: >"$root/dir/file_$i"
		i=$((i + 1))
	done
	project_path_gateway_init "$root" || fail_test '초기화 실패'
	start=$(date +%s)
	run_capture project_path_gateway_verify
	elapsed=$(($(date +%s) - start))
	assert_status 0
	assert_stdout_eq 'project-path-gateway: 검증 통과 200건'
	if [ "$elapsed" -gt 2 ]; then
		printf '경고: 항목 200개 검증에 %s초 걸림 (기준 2초)\n' "$elapsed" >&2
	fi
}
