# 도메인 단위 테스트: 키 규칙 (FR-014, research R-04)

key_verdict() {
	# $1: 로캘, $2: 키
	if LC_ALL=$1 "$TEST_SHELL" -c '. "$REPO_ROOT/lib/project-path-gateway.sh"; project_path_gateway__domain_is_valid_key "$1"' _ "$2"; then
		printf 'valid\n'
	else
		printf 'invalid\n'
	fi
}

check_key() {
	# $1: 기대 판정, $2: 키
	for loc in C en_US.UTF-8; do
		assert_eq "$(key_verdict "$loc" "$2")" "$1" "키 [$2], LC_ALL=$loc"
	done
}

test_valid_keys() {
	check_key valid A
	check_key valid APP_CONFIG
	check_key valid A1_B2
}

test_invalid_keys() {
	cr=$(printf '\r')
	check_key invalid ''
	check_key invalid a
	check_key invalid Abc
	check_key invalid 1A
	check_key invalid _A
	check_key invalid A-B
	check_key invalid 'A B'
	check_key invalid 'AÉ'
	check_key invalid 'A '
	check_key invalid "A$cr"
	check_key invalid b
	check_key invalid z
}
