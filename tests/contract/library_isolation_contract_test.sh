# 계약 테스트: 호출 셸 격리 (사용자 스토리 4, contracts/library-api.md 1절·8절, FR-050~FR-054)
# 각 경우를 별도 셸 프로세스에서 실행하고, 그 프로세스가 발견한 차이를 출력하게 한다.

setup() {
	root="$TEST_TMP/루트 root"
	make_project "$root" 'A=a b/*
MISSING=nope
'
	mkdir -p "$root/a b/*"
	lib=$(lib_path "$root")
}

# 세 공개 함수를 성공·실패 경로로 모두 호출한다. 호출 셸에서 정의해 쓰는 스크립트 조각이다.
CALLS='
project_path_gateway_init "$ROOT" || :
project_path_gateway_get A || :
project_path_gateway_get NOPE || :
project_path_gateway_get || :
project_path_gateway_verify || :
project_path_gateway_verify extra || :
project_path_gateway_init relative || :
project_path_gateway_get A || :
project_path_gateway_init "$ROOT" || :
'

# 시나리오 1
test_set_eu_caller_is_not_terminated() {
	setup
	run_capture in_shell '
		set -eu
		. "$1"
		ROOT=$2
		if project_path_gateway_init "$ROOT"; then :; fi
		if project_path_gateway_get A >/dev/null; then :; fi
		if project_path_gateway_get NOPE 2>/dev/null; then :; fi
		status=0
		project_path_gateway_verify >/dev/null 2>&1 || status=$?
		printf "verify=%s\n" "$status"
		status=0
		project_path_gateway_init /nonexistent/ppg 2>/dev/null || status=$?
		printf "init=%s\n" "$status"
		status=0
		project_path_gateway_get A 2>/dev/null || status=$?
		printf "get=%s\n" "$status"
		printf "alive\n"
	' _ "$lib" "$root"
	assert_status 0
	printf 'verify=1\ninit=2\nget=2\nalive\n' >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/stdout" || fail_test '호출 셸이 끝나거나 반환값이 다름'
}

# 시나리오 2
test_working_directory_options_and_traps_unchanged() {
	setup
	run_capture in_shell '
		ROOT=$2
		set -u -f
		trap "echo t" USR1
		cd "$ROOT/a b" || exit 9
		pwd >"$TEST_TMP/pwd.before"
		set +o >"$TEST_TMP/opts.before"
		trap >"$TEST_TMP/trap.before"
		. "$1"
		eval "$3" >/dev/null 2>&1
		pwd >"$TEST_TMP/pwd.after"
		set +o >"$TEST_TMP/opts.after"
		trap >"$TEST_TMP/trap.after"
		cmp -s "$TEST_TMP/pwd.before" "$TEST_TMP/pwd.after" || echo pwd-changed
		cmp -s "$TEST_TMP/opts.before" "$TEST_TMP/opts.after" || echo options-changed
		cmp -s "$TEST_TMP/trap.before" "$TEST_TMP/trap.after" || echo trap-changed
		[ -s "$TEST_TMP/trap.before" ] || echo trap-not-recorded
		echo done
	' _ "$lib" "$root" "$CALLS"
	assert_status 0
	assert_stdout_eq 'done'
}

# 시나리오 3
test_caller_variables_unchanged() {
	setup
	run_capture in_shell '
		ROOT=$2
		root=r1 key=k1 path=p1 line=l1 entry=e1 dir=d1 status=s1 file=f1 code=c1 first=f2 seen=s2
		lineno=n1 bad=b1 records=r2 record=r3 tab=t1 rest=r4 result=r5 detail=d2 start=s3 current=c2
		count=c3 parent=p2 name=n2 target=t2 physical=p3 full=f3 passed=p4 failed=f4 message=m1
		violation=v1 cr=c4 has_cr=h1 other=o1
		IFS=":"
		saved_ifs=$IFS
		unset IFS
		IFS=$saved_ifs
		set >"$TEST_TMP/vars.before"
		. "$1"
		eval "$3" >/dev/null 2>&1
		for v in root key path line entry dir status file code first seen lineno bad records record tab rest result detail start current count parent name target physical full passed failed message violation cr has_cr other; do
			eval "printf \"%s=%s\n\" \"\$v\" \"\${$v-UNSET}\""
		done
		printf "IFS=[%s]\n" "$IFS"
	' _ "$lib" "$root" "$CALLS"
	assert_status 0
	printf '%s\n' root=r1 key=k1 path=p1 line=l1 entry=e1 dir=d1 status=s1 file=f1 code=c1 first=f2 seen=s2 \
		lineno=n1 bad=b1 records=r2 record=r3 tab=t1 rest=r4 result=r5 detail=d2 start=s3 current=c2 \
		count=c3 parent=p2 name=n2 target=t2 physical=p3 full=f3 passed=p4 failed=f4 message=m1 \
		violation=v1 cr=c4 has_cr=h1 other=o1 'IFS=[:]' >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/stdout" || fail_test '호출자 변수가 바뀜'
}

run_calls_with() {
	# $1: 호출 전에 실행할 설정 코드. 공개 함수 출력과 반환값을 순서대로 기록한다.
	in_shell '
		ROOT=$2
		. "$1"
		eval "$4"
		for call in "init:$ROOT" "get:A" "get:NOPE" "verify:" "init:relative" "get:A" "init:$ROOT" "verify:"; do
			fn=${call%%:*}
			arg=${call#*:}
			if [ -n "$arg" ]; then
				"project_path_gateway_$fn" "$arg"
			else
				"project_path_gateway_$fn"
			fi
			echo "status=$?"
		done
	' _ "$lib" "$root" '' "$1" >"$TEST_TMP/out.$2" 2>&1
}

# 시나리오 4
test_caller_ifs_noglob_and_cdpath_do_not_change_results() {
	setup
	mkdir -p "$TEST_TMP/cdpath/relative"
	run_calls_with ':' default
	run_calls_with 'IFS=/; set -f; CDPATH=$TEST_TMP/cdpath; export CDPATH' modified
	run_calls_with 'set -u' nounset
	grep -F 'status=0' "$TEST_TMP/out.default" >/dev/null || fail_test '기본 실행에 성공 호출이 없음'
	cmp -s "$TEST_TMP/out.default" "$TEST_TMP/out.modified" || fail_test 'IFS=/, set -f, CDPATH에서 결과가 다름'
	cmp -s "$TEST_TMP/out.default" "$TEST_TMP/out.nounset" || fail_test 'set -u에서 결과가 다름'
}

# FR-054: source 시점 부작용 없음, 재 source 시 루트 유지
test_source_has_no_side_effects_and_keeps_root() {
	setup
	run_capture in_shell '
		set | grep -v -e "^_=" -e "^BASH" -e "^PIPESTATUS=" -e "^LINENO=" >"$TEST_TMP/set.before"
		. "$1" >"$TEST_TMP/source.out" 2>&1
		set | grep -v -e "^_=" -e "^BASH" -e "^PIPESTATUS=" -e "^LINENO=" >"$TEST_TMP/set.after"
		[ -s "$TEST_TMP/source.out" ] && echo source-output
		cmp -s "$TEST_TMP/set.before" "$TEST_TMP/set.after" || { echo variables-changed; diff "$TEST_TMP/set.before" "$TEST_TMP/set.after" >&2; }
		project_path_gateway_init "$2" || echo init-failed
		saved=$PROJECT_PATH_GATEWAY_ROOT
		. "$1"
		[ "${PROJECT_PATH_GATEWAY_ROOT-}" = "$saved" ] || echo root-lost
		project_path_gateway_get A >/dev/null || echo get-failed
		set | grep "^PROJECT_PATH_GATEWAY_" | sed "s/=.*//"
		export -p | grep PROJECT_PATH_GATEWAY_ && echo exported
		echo done
	' _ "$lib" "$root"
	assert_status 0
	printf 'PROJECT_PATH_GATEWAY_ROOT\ndone\n' >"$TEST_TMP/want"
	cmp -s "$TEST_TMP/want" "$TEST_TMP/stdout" || fail_test 'source 부작용 또는 접두어 변수 문제'
}

# FR-050, FR-062
test_library_source_has_no_exit_word() {
	if grep -i -w -e exit -e git "$REPO_ROOT/lib/project-path-gateway.sh" >/dev/null; then
		fail_test '라이브러리에 exit 또는 git 단어가 있음'
	fi
}
