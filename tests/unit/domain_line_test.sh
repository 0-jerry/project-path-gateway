# 도메인 단위 테스트: 줄 분류와 중복 키 검사 (FR-012~FR-016, data-model 1.5)

. "$REPO_ROOT/lib/project-path-gateway.sh"

check_line() {
	# $1: 기대 분류, $2: 줄
	actual=$(project_path_gateway__domain_classify_line "$2")
	assert_eq "$actual" "$1" "줄 [$2]"
}

test_classify_ignored_lines() {
	check_line ignore ''
	check_line ignore '#x'
	check_line ignore '#'
	check_line ignore '# A=/etc'
	check_line ignore "#x$(printf '\r')"
}

test_classify_violations() {
	cr=$(printf '\r')
	check_line no_separator ' '
	check_line no_separator '	'
	check_line no_separator ' #x'
	check_line no_separator 'abc'
	check_line no_separator "$cr"
	check_line invalid_key 'a=b'
	check_line invalid_key 'A =b'
	check_line invalid_key '=b'
	check_line invalid_key "A$cr=b"
	check_line empty_path 'A='
	check_line absolute_path 'A=/etc/hosts'
	check_line parent_segment 'A=a/../b'
	check_line carriage_return "A=b$cr"
}

test_classify_entries() {
	check_line entry 'A=b'
	check_line entry 'A= b'
	check_line entry 'A=b=c'
	check_line entry 'APP_CONFIG=config/app.json'
}

test_line_key_and_path() {
	assert_eq "$(project_path_gateway__domain_line_key 'A= b')" 'A' '키'
	assert_eq "$(project_path_gateway__domain_line_path 'A= b')" ' b' '경로 앞 공백 유지'
	assert_eq "$(project_path_gateway__domain_line_key 'A=b=c')" 'A' '첫 = 앞'
	assert_eq "$(project_path_gateway__domain_line_path 'A=b=c')" 'b=c' '첫 = 뒤 전체'
	assert_eq "$(project_path_gateway__domain_line_path 'A=b ')" 'b ' '경로 끝 공백 유지'
}

test_seen_keys() {
	seen=
	assert_eq "$(project_path_gateway__domain_seen_lineno "$seen" A)" '' '빈 목록'
	seen=$(project_path_gateway__domain_seen_add "$seen" AB 2)
	seen=$(project_path_gateway__domain_seen_add "$seen" A 5)
	seen=$(project_path_gateway__domain_seen_add "$seen" B_1 9)
	assert_eq "$(project_path_gateway__domain_seen_lineno "$seen" A)" 5 'A'
	assert_eq "$(project_path_gateway__domain_seen_lineno "$seen" AB)" 2 'AB'
	assert_eq "$(project_path_gateway__domain_seen_lineno "$seen" B_1)" 9 'B_1'
	assert_eq "$(project_path_gateway__domain_seen_lineno "$seen" B)" '' '접두어만 같은 키'
	assert_eq "$(project_path_gateway__domain_seen_lineno "$seen" C)" '' '없는 키'
}
