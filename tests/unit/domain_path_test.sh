# 도메인 단위 테스트: 경로 규칙 (FR-015)

. "$REPO_ROOT/lib/project-path-gateway.sh"

check_path() {
	# $1: 기대 원인 코드(없으면 빈 문자열), $2: 경로
	actual=$(project_path_gateway__domain_path_violation "$2")
	assert_eq "$actual" "$1" "경로 [$2]"
}

test_violations() {
	cr=$(printf '\r')
	check_path empty_path ''
	check_path absolute_path /etc
	check_path absolute_path /
	check_path parent_segment ..
	check_path parent_segment ../a
	check_path parent_segment a/..
	check_path parent_segment a/../b
	check_path carriage_return "a$cr"
	check_path carriage_return "a${cr}b"
}

test_allowed_paths() {
	for p in 'a b' '한글/경로' 'a=b' './a' 'a//b' 'dir/' '-a' '...' '..a' 'a..' '.' 'a/./b'; do
		check_path '' "$p"
	done
}
