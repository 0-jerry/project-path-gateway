# 포트 대체물 (specs/002-dry-run-unit-tests/contracts/doubles.md 3절)
#
# 대상 파일을 불러온 뒤 ppgt_stub_apply <대상 파일>을 호출하면, 그 파일에 정의된 __port_* 함수를 모두 대체 함수로 바꾼다.
# 대체 함수는 op port 기록을 남기고 사례 stub 응답 중 함수 이름과 인자가 모두 같은 첫 응답을 출력·반환한다.
# 일치하는 응답이 없으면 op unmatched-stub을 기록하고 125를 반환한다.

# 인자 목록을 토큰 표기로 공백 연결한다.
ppgt_stub_key() {
	ppgt_stub_key_v=
	for ppgt_stub_key_arg in "$@"; do
		ppgt_stub_key_v="$ppgt_stub_key_v $(ppgt_enc "$ppgt_stub_key_arg")"
	done
	printf '%s' "$ppgt_stub_key_v"
}

# 사례 stub 응답 한 건(ppgt_case_stubs가 호출). $1: 함수, $2: 반환값, $3: stdout, $4: stderr, 나머지: 인자
ppgt_stub() {
	[ "$PPGT_STUB_FOUND" = 0 ] || return 0
	[ "$1" = "$PPGT_STUB_NAME" ] || return 0
	ppgt_stub_ret=$2
	ppgt_stub_out=$3
	ppgt_stub_err=$4
	shift 4
	[ "$(ppgt_stub_key "$@")" = "$PPGT_STUB_ARGS" ] || return 0
	PPGT_STUB_FOUND=1
	PPGT_STUB_RET=$ppgt_stub_ret
	PPGT_STUB_OUT=$ppgt_stub_out
	PPGT_STUB_ERR=$ppgt_stub_err
}

# 포트 대체 본문. $1: 포트 함수 이름, 나머지: 인자
ppgt_port_call() {
	PPGT_STUB_NAME=$1
	shift
	ppgt_rec port "$PPGT_STUB_NAME" "$@"
	PPGT_STUB_ARGS=$(ppgt_stub_key "$@")
	PPGT_STUB_FOUND=0
	ppgt_case_stubs
	if [ "$PPGT_STUB_FOUND" != 1 ]; then
		ppgt_rec unmatched-stub "$PPGT_STUB_NAME" "$@"
		return 125
	fi
	printf '%s' "$PPGT_STUB_OUT"
	printf '%s' "$PPGT_STUB_ERR" >&2
	return "$PPGT_STUB_RET"
}

# 대상 파일에 정의된 __port_* 함수를 대체한다. $1: 대상 파일
ppgt_stub_apply() {
	ppgt_stub_names=$(LC_ALL=C "$PPGT_SED" -n 's/^\([a-z_]*__port_[a-z_]*\)() .*/\1/p' "$1")
	ppgt_stub_rest=$ppgt_stub_names
	while [ -n "$ppgt_stub_rest" ]; do
		ppgt_stub_one=${ppgt_stub_rest%%"$PPGT_NL"*}
		case $ppgt_stub_rest in
		*"$PPGT_NL"*) ppgt_stub_rest=${ppgt_stub_rest#*"$PPGT_NL"} ;;
		*) ppgt_stub_rest= ;;
		esac
		eval "$ppgt_stub_one() { ppgt_port_call $ppgt_stub_one \"\$@\"; }"
	done
}
