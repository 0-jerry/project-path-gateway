# 통합 테스트: 전역 프로그램 프로젝트 초기화 (사용자 스토리 0, FR-080~FR-087, research R-10)

setup() {
	prefix="$TEST_TMP/prefix"
	install_to "$prefix" || fail_test '설치 실패'
	ppg="$prefix/bin/project-path-gateway"
	source_lib="$prefix/share/project-path-gateway/project-path-gateway.sh"
}

tool_dir() {
	printf '%s\n' "$1/.tool/project-path-gateway"
}

# 시나리오 1, 6
test_init_without_argument() {
	setup
	project="$TEST_TMP/project"
	mkdir -p "$project"
	: >"$project/existing"
	cd "$project" || fail_test cd
	run_capture "$ppg" init
	assert_status 0
	assert_file_exists "$(tool_dir "$project")/.project-path-gateway"
	assert_file_exists "$(conf_path "$project")"
	assert_file_exists "$(lib_path "$project")"
	assert_eq "$(dir_entries "$project" | tr '\n' ' ')" '.tool existing ' '루트 바로 아래 항목'
	assert_not_exists "$project/.git"
}

# 시나리오 4
test_init_with_path_from_outside() {
	setup
	project="$TEST_TMP/project"
	mkdir -p "$project" "$TEST_TMP/cwd"
	cd "$TEST_TMP/cwd" || fail_test cd
	run_capture "$ppg" init "$project"
	assert_status 0
	assert_file_exists "$(lib_path "$project")"
	assert_eq "$(dir_entries "$TEST_TMP/cwd")" '' '현재 작업 디렉터리'
}

test_relative_target_argument() {
	setup
	mkdir -p "$TEST_TMP/rel/project"
	cd "$TEST_TMP/rel" || fail_test cd
	run_capture "$ppg" init project
	assert_status 0
	assert_file_exists "$(lib_path "$TEST_TMP/rel/project")"
}

# 시나리오 7
test_rerun_replaces_only_library() {
	setup
	project="$TEST_TMP/project"
	mkdir -p "$project"
	"$ppg" init "$project" >/dev/null || fail_test '첫 초기화 실패'
	tool=$(tool_dir "$project")
	printf 'APP_CONFIG=config/app.json\n' >>"$tool/project-path-gateway.conf"
	printf '# project-path-gateway 0.0.1\n' >"$tool/project-path-gateway.sh"
	cp "$tool/project-path-gateway.conf" "$TEST_TMP/conf.copy"
	cp "$tool/.project-path-gateway" "$TEST_TMP/marker.copy"
	conf_inode=$(inode_of "$tool/project-path-gateway.conf")
	marker_inode=$(inode_of "$tool/.project-path-gateway")
	time_ref "$TEST_TMP/ref"

	run_capture "$ppg" init "$project"
	assert_status 0
	cmp -s "$source_lib" "$tool/project-path-gateway.sh" || fail_test '라이브러리가 교체되지 않음'
	cmp -s "$TEST_TMP/conf.copy" "$tool/project-path-gateway.conf" || fail_test '데이터 파일 내용이 바뀜'
	cmp -s "$TEST_TMP/marker.copy" "$tool/.project-path-gateway" || fail_test '표식 파일 내용이 바뀜'
	assert_eq "$(inode_of "$tool/project-path-gateway.conf")" "$conf_inode" '데이터 파일 inode'
	assert_eq "$(inode_of "$tool/.project-path-gateway")" "$marker_inode" '표식 파일 inode'
	changed=$(changed_since "$TEST_TMP/ref" "$tool")
	case $changed in
	*project-path-gateway.conf* | *.project-path-gateway*) fail_test "수정 시각이 바뀜: $changed" ;;
	esac
}

# 시나리오 8
test_recreates_deleted_data_file() {
	setup
	project="$TEST_TMP/project"
	mkdir -p "$project"
	"$ppg" init "$project" >/dev/null || fail_test '첫 초기화 실패'
	rm "$(conf_path "$project")"
	run_capture "$ppg" init "$project"
	assert_status 0
	assert_stdout_contains '생성: .tool/project-path-gateway/project-path-gateway.conf'
	run_capture in_shell '. "$1"; project_path_gateway_init "$2" && project_path_gateway_verify' _ "$(lib_path "$project")" "$project"
	assert_status 0
	assert_stdout_eq 'project-path-gateway: 검증 통과 0건'
}

# 시나리오 9
test_no_machine_specific_values_recorded() {
	setup
	project="$TEST_TMP/project"
	mkdir -p "$project"
	"$ppg" init "$project" >/dev/null || fail_test '초기화 실패'
	for value in "$project" "$(physical "$project")" "$HOME" "$TEST_TMP"; do
		if grep -r -F -e "$value" "$project/.tool" >/dev/null; then
			fail_test "기록되면 안 되는 값: $value"
		fi
	done
	if [ -n "${USER-}" ] && grep -r -w -F -e "$USER" "$project/.tool" >/dev/null; then
		fail_test "사용자 이름이 기록됨: $USER"
	fi
}

# 시나리오 10
test_other_tool_entries_untouched() {
	setup
	project="$TEST_TMP/project"
	mkdir -p "$project/.tool/other"
	printf 'other\n' >"$project/.tool/other/config"
	printf 'top\n' >"$project/.tool/top-file"
	time_ref "$TEST_TMP/ref"
	before=$(tree_list "$project/.tool")
	run_capture "$ppg" init "$project"
	assert_status 0
	after=$(tree_list "$project/.tool" | grep -v '^\./project-path-gateway')
	assert_eq "$after" "$before" '.tool 다른 항목 목록'
	changed=$(changed_since "$TEST_TMP/ref" "$project/.tool" | grep -v -e '/\.tool$' -e '/\.tool/project-path-gateway')
	assert_eq "$changed" '' '.tool 다른 항목 수정'
}

# 쓰기 실패: 기존 파일 보존, 임시 파일 없음 (공백·한글 경로 포함)
test_write_failure_keeps_existing_files() {
	[ "$(id -u)" != 0 ] || skip_test 'root 사용자는 권한 제한이 적용되지 않음'
	setup
	for name in project '내 프로젝트 폴더'; do
		project="$TEST_TMP/$name"
		mkdir -p "$project"
		"$ppg" init "$project" >/dev/null || fail_test '첫 초기화 실패'
		tool=$(tool_dir "$project")
		cp "$tool/project-path-gateway.conf" "$TEST_TMP/conf.copy"
		cp "$tool/.project-path-gateway" "$TEST_TMP/marker.copy"
		rm "$tool/project-path-gateway.sh"
		chmod 555 "$tool"
		run_capture "$ppg" init "$project"
		chmod 755 "$tool"
		assert_status 1
		assert_stderr_contains 'project-path-gateway: init: 파일을 쓰지 못했습니다: '
		cmp -s "$TEST_TMP/conf.copy" "$tool/project-path-gateway.conf" || fail_test '데이터 파일이 바뀜'
		cmp -s "$TEST_TMP/marker.copy" "$tool/.project-path-gateway" || fail_test '표식 파일이 바뀜'
		assert_eq "$(dir_entries "$tool" | grep -c '^\.ppg-tmp\.')" 0 "임시 파일 잔존 ($name)"
	done
}

test_symlinked_program_finds_library_source() {
	setup
	mkdir -p "$TEST_TMP/linkbin" "$TEST_TMP/project"
	ln -s "$ppg" "$TEST_TMP/linkbin/ppg"
	run_capture "$TEST_TMP/linkbin/ppg" init "$TEST_TMP/project"
	assert_status 0
	cmp -s "$source_lib" "$(lib_path "$TEST_TMP/project")" || fail_test '생성된 라이브러리가 원본과 다름'
	cmp -s "$REPO_ROOT/lib/project-path-gateway.sh" "$(lib_path "$TEST_TMP/project")" || fail_test '저장소 원본과 다름'
}

test_missing_library_source() {
	setup
	rm "$source_lib"
	mkdir -p "$TEST_TMP/project"
	run_capture "$ppg" init "$TEST_TMP/project"
	assert_status 1
	assert_stderr_contains '라이브러리 원본을 찾지 못했습니다'
	assert_not_exists "$TEST_TMP/project/.tool"
}

# 임시 파일 정리 trap (research R-10): 자기 PID 임시 파일만 지우고 신호별 반환값으로 끝난다
run_trap_case() {
	# $1: 신호(TERM, INT) 또는 exit, $2: 대상 디렉터리
	in_shell '
		PPG_SOURCE_ONLY=1
		. "$1"
		ppg__if_set_traps "$2"
		tool="$2/.tool/project-path-gateway"
		: >"$tool/.ppg-tmp.$$.x"
		: >"$tool/.ppg-tmp.1.x"
		case $3 in
		exit) exit 0 ;;
		*) kill -"$3" $$ ;;
		esac
		sleep 2
	' _ "$ppg" "$2" "$1"
}

test_traps_clean_only_own_temp_files() {
	setup
	target="$TEST_TMP/공백 있는 대상"
	mkdir -p "$target/.tool/project-path-gateway"
	for case_name in TERM:143 INT:130 exit:0; do
		rm -f "$target/.tool/project-path-gateway/".ppg-tmp.*
		run_trap_case "${case_name%%:*}" "$target"
		status=$?
		assert_eq "$status" "${case_name#*:}" "${case_name%%:*} 반환값"
		assert_eq "$(dir_entries "$target/.tool/project-path-gateway")" '.ppg-tmp.1.x' "${case_name%%:*} 뒤 남은 임시 파일"
	done
}
