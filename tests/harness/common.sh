# 하니스 공통 함수
#
# 사례 프로세스(tests/harness/case.sh)와 대체물이 불러온다. 함수는 ppgt_, 전역 변수는 PPGT_ 접두어를 쓴다.
# 작업 기록은 fd 9에 쓴다(specs/002-dry-run-unit-tests/contracts/doubles.md 1절).

PPGT_NL='
'
PPGT_TAB=$(printf '\t')
PPGT_CR=$(printf '\r')
# 사례 env PATH가 바뀌어도 하니스가 쓰는 유틸리티를 찾도록 불러올 때 경로를 고정한다.
PPGT_AWK=$(command -v awk)
PPGT_SED=$(command -v sed)

# 값을 토큰 표기로 출력한다(contracts/case-file.md 2절). 끝 개행을 붙이지 않는다.
ppgt_enc() {
	case $1 in
	'')
		printf '%s' '\e'
		return 0
		;;
	*" "* | *"$PPGT_TAB"* | *"$PPGT_CR"* | *"$PPGT_NL"* | *\\*) ;;
	*)
		printf '%s' "$1"
		return 0
		;;
	esac
	printf '%s' "$1" | LC_ALL=C "$PPGT_AWK" 'BEGIN { RS = "\001" }
	{
		n = length($0); o = ""
		for (i = 1; i <= n; i++) {
			c = substr($0, i, 1)
			if (c == "\\") o = o "\\\\"
			else if (c == "\t") o = o "\\t"
			else if (c == "\r") o = o "\\r"
			else if (c == "\n") o = o "\\n"
			else if (c == " ") o = o "\\s"
			else o = o c
		}
		printf "%s", o
	}'
}

# 토큰 표기를 바이트로 출력한다.
ppgt_dec() {
	case $1 in
	'\e') return 0 ;;
	*\\*) ;;
	*)
		printf '%s' "$1"
		return 0
		;;
	esac
	ppgt_dec_v=$(printf '%s\n' "$1" | "$PPGT_SED" -e 's/\\\\/\\0134/g' -e 's/\\s/\\0040/g' -e 's/\\t/\\0011/g' -e 's/\\r/\\0015/g' -e 's/\\n/\\0012/g')
	printf '%b' "$ppgt_dec_v"
}

# 작업 기록 한 줄: op KIND 토큰...
ppgt_rec() {
	ppgt_rec_line="op $1"
	shift
	for ppgt_rec_arg in "$@"; do
		ppgt_rec_line="$ppgt_rec_line $(ppgt_enc "$ppgt_rec_arg")"
	done
	{ printf '%s\n' "$ppgt_rec_line" >&9; } 2>/dev/null
	return 0
}

# 대체물 적용: 사례 doubles 값에 따라 포트 또는 시스템 대체물을 불러온다. $1: 대상 소스 파일
ppgt_apply_doubles() {
	case $PPGT_DOUBLES in
	ports) ppgt_apply_file=stub.sh ;;
	system) ppgt_apply_file=vfs.sh ;;
	*) return 0 ;;
	esac
	if [ ! -f "$PPGT_ROOT/tests/harness/$ppgt_apply_file" ]; then
		printf 'harness: 대체물 파일이 없습니다: tests/harness/%s\n' "$ppgt_apply_file" >&2
		return 125
	fi
	# shellcheck source=/dev/null
	. "$PPGT_ROOT/tests/harness/$ppgt_apply_file"
	case $PPGT_DOUBLES in
	ports) ppgt_stub_apply "$1" ;;
	*) ppgt_vfs_apply ;;
	esac
}
