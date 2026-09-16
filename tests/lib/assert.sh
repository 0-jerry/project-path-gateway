# 테스트 단언 함수
#
# tests/run.sh가 테스트 함수 하나마다 새 셸 프로세스에서 이 파일을 불러온다.
# 단언이 실패하면 기대값과 실제값을 stderr에 출력하고 테스트 프로세스를 상태 1로 끝낸다.
# 호출 결과는 $TEST_TMP/stdout, $TEST_TMP/stderr, CAPTURED_STATUS에 기록한다.

# 명령을 서브셸에서 실행해 출력과 반환값을 기록한다. 셸 상태 변경은 남지 않는다.
run_capture() {
	if ("$@") >"$TEST_TMP/stdout" 2>"$TEST_TMP/stderr"; then
		CAPTURED_STATUS=0
	else
		CAPTURED_STATUS=$?
	fi
}

# 명령을 현재 셸에서 실행해 출력과 반환값을 기록한다. 셸 상태 변경이 남는다.
run_here() {
	if "$@" >"$TEST_TMP/stdout" 2>"$TEST_TMP/stderr"; then
		CAPTURED_STATUS=0
	else
		CAPTURED_STATUS=$?
	fi
}

fail_test() {
	printf 'FAIL: %s\n' "$1" >&2
	if [ -f "$TEST_TMP/stdout" ]; then
		printf -- '--- stdout ---\n' >&2
		cat "$TEST_TMP/stdout" >&2
	fi
	if [ -f "$TEST_TMP/stderr" ]; then
		printf -- '--- stderr ---\n' >&2
		cat "$TEST_TMP/stderr" >&2
	fi
	exit 1
}

skip_test() {
	printf 'SKIP: %s\n' "$1" >&2
	exit 77
}

assert_status() {
	[ "$CAPTURED_STATUS" = "$1" ] ||
		fail_test "반환값 기대 $1, 실제 $CAPTURED_STATUS"
}

assert_stdout_eq() {
	printf '%s\n' "$1" >"$TEST_TMP/expected"
	cmp -s "$TEST_TMP/expected" "$TEST_TMP/stdout" ||
		fail_test "stdout 기대: [$1]"
}

assert_stdout_empty() {
	[ ! -s "$TEST_TMP/stdout" ] || fail_test "stdout이 비어 있어야 함"
}

assert_stdout_contains() {
	grep -F -e "$1" "$TEST_TMP/stdout" >/dev/null ||
		fail_test "stdout에 포함되어야 함: [$1]"
}

assert_stderr_contains() {
	grep -F -e "$1" "$TEST_TMP/stderr" >/dev/null ||
		fail_test "stderr에 포함되어야 함: [$1]"
}

assert_stderr_not_contains() {
	if grep -F -e "$1" "$TEST_TMP/stderr" >/dev/null; then
		fail_test "stderr에 포함되지 않아야 함: [$1]"
	fi
}

assert_stderr_empty() {
	[ ! -s "$TEST_TMP/stderr" ] || fail_test "stderr가 비어 있어야 함"
}

# N번째 줄이 TEXT와 같은지 확인한다. N이 -1이면 마지막 줄이다.
assert_stderr_line() {
	if [ "$1" = -1 ]; then
		actual=$(tail -n 1 "$TEST_TMP/stderr")
	else
		actual=$(sed -n "$1p" "$TEST_TMP/stderr")
	fi
	[ "$actual" = "$2" ] ||
		fail_test "stderr $1번째 줄 기대: [$2], 실제: [$actual]"
}

assert_stderr_lines() {
	actual=$(wc -l <"$TEST_TMP/stderr" | tr -d ' ')
	[ "$actual" = "$1" ] ||
		fail_test "stderr 줄 수 기대 $1, 실제 $actual"
}

assert_eq() {
	[ "$1" = "$2" ] || fail_test "${3:-값 비교}: 기대 [$2], 실제 [$1]"
}

assert_file_exists() {
	[ -f "$1" ] || fail_test "파일이 있어야 함: $1"
}

assert_not_exists() {
	if [ -e "$1" ] || [ -L "$1" ]; then
		fail_test "없어야 함: $1"
	fi
}

# N번째 줄(-1은 마지막 줄)에 TEXT가 포함되는지 확인한다.
assert_stderr_line_contains() {
	if [ "$1" = -1 ]; then
		actual=$(tail -n 1 "$TEST_TMP/stderr")
	else
		actual=$(sed -n "$1p" "$TEST_TMP/stderr")
	fi
	case $actual in
	*"$2"*) ;;
	*) fail_test "stderr $1번째 줄에 포함되어야 함: [$2], 실제: [$actual]" ;;
	esac
}
