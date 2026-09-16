# 시스템 대체물 (specs/002-dry-run-unit-tests/contracts/doubles.md 1·2절, data-model.md 1.6·2.2·2.3)
#
# 대상 파일을 불러온 뒤 ppgt_vfs_apply를 호출하면 project_path_gateway__sys_*, ppg__sys_* 함수를 가상 파일 시스템
# 위에서 동작하는 대체 함수로 바꾼다. 항목 표는 셸 변수 PPGT_VFS에 두고, 포트 호출마다 tests/harness/vfs.awk가
# 표를 읽어 응답·기록·갱신을 계산한다. 실제 파일 시스템에는 접근하지 않는다.

PPGT_VFS=
PPGT_VFS_FAULTS=
PPGT_VFS_MUT=0

# 사례 fs 항목 추가. $1: 종류, $2: 경로, $3: 내용 또는 링크 대상
ppgt_vfs_add() {
	PPGT_VFS="$PPGT_VFS$1$PPGT_TAB$(ppgt_enc "$2")$PPGT_TAB$(ppgt_enc "${3-}")$PPGT_NL"
}

# 사례 fault 항목 추가. $1: 작업 종류, $2: 경로
ppgt_fault() {
	PPGT_VFS_FAULTS="$PPGT_VFS_FAULTS$1$PPGT_TAB$(ppgt_enc "$2")$PPGT_NL"
}

# vfs.awk 연산 하나를 실행한다. 결과: ppgt_vfs_st(반환값), ppgt_vfs_op(기록 줄), ppgt_vfs_out(stdout 바이트)
ppgt_vfs_run() {
	ppgt_vfs_res=$(PPGT_VFS=$PPGT_VFS PPGT_FAULTS=$PPGT_VFS_FAULTS PPGT_OP=$1 PPGT_A1=${2-} PPGT_A2=${3-} \
		PPGT_VCWD=$PPGT_VFS_CWD PPGT_PATHS=${PPGT_CASE_PATH-} LC_ALL=C "$PPGT_AWK" -f "$PPGT_ROOT/tests/harness/vfs.awk")
	ppgt_vfs_st=${ppgt_vfs_res%%"$PPGT_NL"*}
	ppgt_vfs_res=${ppgt_vfs_res#*"$PPGT_NL"}
	ppgt_vfs_op=${ppgt_vfs_res%%"$PPGT_NL"*}
	ppgt_vfs_res=${ppgt_vfs_res#*"$PPGT_NL"}
	ppgt_vfs_changed=${ppgt_vfs_res%%"$PPGT_NL"*}
	ppgt_vfs_res=${ppgt_vfs_res#*"$PPGT_NL"}
	if [ "$ppgt_vfs_changed" = 1 ]; then
		PPGT_VFS=${ppgt_vfs_res%%"$PPGT_NL.$PPGT_NL"*}$PPGT_NL
		ppgt_vfs_res=${ppgt_vfs_res#*"$PPGT_NL.$PPGT_NL"}
	fi
	ppgt_vfs_out=${ppgt_vfs_res%x}
}

# 신호 번호
ppgt_signum() {
	case $1 in
	HUP) printf '1\n' ;;
	INT) printf '2\n' ;;
	TERM) printf '15\n' ;;
	*) printf '0\n' ;;
	esac
}

# 변경 작업 직전 중단 주입(data-model 2.3). 기억한 trap 동작을 현재 셸에서 실행하거나 128+번호로 끝낸다.
ppgt_vfs_interrupt() {
	PPGT_VFS_MUT=$((PPGT_VFS_MUT + 1))
	[ -n "${PPGT_INT_SIG-}" ] || return 0
	[ "$PPGT_VFS_MUT" = "$PPGT_INT_N" ] || return 0
	ppgt_vfs_action=
	eval "ppgt_vfs_isset=\${PPGT_TRAP_$PPGT_INT_SIG+x}"
	eval "ppgt_vfs_action=\${PPGT_TRAP_$PPGT_INT_SIG-}"
	if [ -n "$ppgt_vfs_isset" ] && [ "$ppgt_vfs_action" != - ]; then
		eval "$ppgt_vfs_action"
		return 0
	fi
	exit $((128 + $(ppgt_signum "$PPGT_INT_SIG")))
}

# 발화용 EXIT trap이 호출한다. 기억한 동작을 대체물 위에서 실행한다.
ppgt_vfs_fire() {
	eval "ppgt_vfs_action=\${PPGT_TRAP_$1-}"
	eval "$ppgt_vfs_action"
}

# 시스템 포트 대체 본문. $1: 포트 접미사, 나머지: 포트 인자
ppgt_vfs_port() {
	case $1 in
	mkdir | mkdir_p | rmdir | remove | write_text | copy_to | link | move | chmod) ppgt_vfs_interrupt ;;
	esac
	case $1 in
	self_path)
		ppgt_rec self-path
		if [ "$PPGT_HAS_SELF" != 1 ]; then
			printf 'harness: 사례에 self가 없습니다\n' >&2
			return 125
		fi
		printf '%sx' "$PPGT_SELF"
		return 0
		;;
	pid)
		ppgt_rec pid
		printf '%s\n' "$PPGT_PID"
		return 0
		;;
	trap)
		ppgt_rec trap "$3" "$2"
		case $2 in
		-) unset "PPGT_TRAP_$3" ;;
		*) eval "PPGT_TRAP_$3=\$2" ;;
		esac
		if [ "$3" = EXIT ]; then
			case $2 in
			-) trap - EXIT ;;
			*) trap 'ppgt_vfs_fire EXIT' EXIT ;;
			esac
		fi
		return 0
		;;
	esac
	ppgt_vfs_run "$1" "${2-}" "${3-}"
	{ printf '%s\n' "$ppgt_vfs_op" >&9; } 2>/dev/null || :
	printf '%s' "$ppgt_vfs_out"
	return "$ppgt_vfs_st"
}

# 사례 fs·fault 입력으로 표를 만들고 시스템 포트 함수를 대체한다.
ppgt_vfs_apply() {
	PPGT_VFS="dir$PPGT_TAB/$PPGT_TAB\\e$PPGT_NL"
	PPGT_VFS_CWD=$PPGT_CWD
	ppgt_case_fs
	ppgt_vfs_run init
	for ppgt_vfs_name in is_dir is_file is_readable exists is_link physical_dir readlink read_lines read_file \
		self_path command_path pid list_prefix mkdir mkdir_p rmdir remove write_text copy_to link move chmod trap; do
		eval "project_path_gateway__sys_$ppgt_vfs_name() { ppgt_vfs_port $ppgt_vfs_name \"\$@\"; }"
		eval "ppg__sys_$ppgt_vfs_name() { ppgt_vfs_port $ppgt_vfs_name \"\$@\"; }"
	done
}
