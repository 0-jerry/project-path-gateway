# 도메인 단위 테스트: 경로 결합과 루트 내부 판정 (FR-021, FR-032)
# 명세 경계 사례 "루트가 /" 행과 "/a/root2 경로와 루트 /a/root" 행의 자동 테스트다 (SC-001).

. "$REPO_ROOT/lib/project-path-gateway.sh"

check_inside() {
	# $1: 기대(yes/no), $2: 루트, $3: 물리 경로
	if project_path_gateway__domain_is_inside "$2" "$3"; then
		actual=yes
	else
		actual=no
	fi
	assert_eq "$actual" "$1" "루트 [$2], 경로 [$3]"
}

test_join() {
	assert_eq "$(project_path_gateway__domain_join /r a)" /r/a '일반'
	assert_eq "$(project_path_gateway__domain_join / a)" /a '루트가 / (슬래시 중복 없음)'
	assert_eq "$(project_path_gateway__domain_join /r ./a)" /r/./a '. 세그먼트 그대로'
	assert_eq "$(project_path_gateway__domain_join /r dir/)" /r/dir/ '끝 / 그대로'
	assert_eq "$(project_path_gateway__domain_join '/내 루트' 'a b/한글')" '/내 루트/a b/한글' '공백·한글'
	assert_eq "$(project_path_gateway__domain_join /r -a)" /r/-a '- 시작'
}

test_is_inside() {
	check_inside yes /a/root /a/root
	check_inside yes /a/root /a/root/x
	check_inside no /a/root /a/root2
	check_inside no /a/root /a
	check_inside no /a/root /b
	check_inside yes / /anything
	check_inside yes / /
	check_inside yes '/내 루트' '/내 루트/a b'
	check_inside no '/내 루트' '/내 루트2/a'
	check_inside no '/a/[r]' /a/r/x
	check_inside yes '/a/*' '/a/*/x'
	check_inside no '/a/*' /a/b/x
}
