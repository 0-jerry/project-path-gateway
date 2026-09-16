# 어댑터: README 사용 예 (specs/002-dry-run-unit-tests/contracts/doubles.md 4.1절)
#
# README.md에서 "<!-- example: 이름 -->" 뒤 첫 sh 코드 블록을 꺼내, 대상 셸의 새 프로세스에서 실행한다.
# $0은 사례 self, 위치 인자는 call 토큰이다. 새 프로세스는 하니스·사례·라이브러리·시스템 대체물을 준비하고
# cd·pwd·dirname을 가상 파일 시스템 기준 함수로 바꾼 뒤, "." source 줄을 op source 기록으로 바꿔 사용 예를 실행한다.

ppgt_shq() {
	ppgt_shq_v=$(printf '%sx' "$1" | "$PPGT_SED" "s/'/'\\\\''/g")
	printf "'%s'" "${ppgt_shq_v%x}"
}

# 새 프로세스 준비 코드. 사용 예를 실행하기 전 환경을 만든다.
# shellcheck disable=SC2016 # 새 셸에서 확장할 코드 문자열이다
PPGT_README_PREP='
. "$PPGT_ROOT/tests/harness/common.sh"
eval "$PPGT_CASE_CODE"
PPGT_CASE_PATH=$PPGT_README_CASE_PATH
. "$PPGT_ROOT/lib/project-path-gateway.sh"
ppgt_apply_doubles "$PPGT_ROOT/lib/project-path-gateway.sh" || exit 125
ppgt_readme_source() {
	ppgt_rec source "$1"
}
cd() {
	ppgt_cd_mode=L
	while [ "$#" -gt 1 ]; do
		case $1 in
		-P) ppgt_cd_mode=P ;;
		-L) ppgt_cd_mode=L ;;
		--) shift; break ;;
		esac
		shift
	done
	ppgt_rec cd "${1-}"
	ppgt_vfs_run cd "${1-}" "$ppgt_cd_mode"
	if [ "$ppgt_vfs_st" != 0 ]; then
		printf "cd: %s: 디렉터리가 아닙니다\n" "${1-}" >&2
		return 1
	fi
	PPGT_VFS_CWD=${ppgt_vfs_out%x}
	return 0
}
pwd() {
	ppgt_rec pwd
	printf "%s\n" "$PPGT_VFS_CWD"
}
dirname() {
	[ "${1-}" != -- ] || shift
	ppgt_dn=${1-}
	case $ppgt_dn in
	"") printf ".\n"; return 0 ;;
	esac
	case $ppgt_dn in
	*[!/]*) ;;
	*) printf "/\n"; return 0 ;;
	esac
	while :; do case $ppgt_dn in */) ppgt_dn=${ppgt_dn%/} ;; *) break ;; esac; done
	case $ppgt_dn in
	*/*) ;;
	*) printf ".\n"; return 0 ;;
	esac
	ppgt_dn=${ppgt_dn%/*}
	while :; do case $ppgt_dn in */) ppgt_dn=${ppgt_dn%/} ;; *) break ;; esac; done
	[ -n "$ppgt_dn" ] || ppgt_dn=/
	printf "%s\n" "$ppgt_dn"
}
eval "$PPGT_EXAMPLE"
'

ppgt_adapter_run() {
	if ! ppgt_readme_block=$(LC_ALL=C "$PPGT_AWK" -v name="$PPGT_TARGET" '
	$0 == "<!-- example: " name " -->" { found = 1; next }
	found == 1 && $0 == "```sh" { inside = 1; found = 2; next }
	inside && $0 == "```" { done = 1; exit }
	inside { print }
	END { if (!done) exit 1 }' "$PPGT_ROOT/README.md") || [ -z "$ppgt_readme_block" ]; then
		printf 'harness: README 사용 예를 찾지 못했습니다: %s\n' "$PPGT_TARGET" >&2
		return 125
	fi
	ppgt_readme_block=$(printf '%s\n' "$ppgt_readme_block" | LC_ALL=C "$PPGT_AWK" '
	/^[ \t]*\. / { sub(/\. /, "ppgt_readme_source "); print; next }
	{ print }')
	ppgt_readme_argv=
	# shellcheck disable=SC2329 # 사례 call 입력(ppgt_case_calls)이 호출한다
	ppgt_call() {
		for ppgt_call_arg in "$@"; do
			ppgt_readme_argv="$ppgt_readme_argv $(ppgt_shq "$ppgt_call_arg")"
		done
	}
	ppgt_case_calls
	eval "set -- $ppgt_readme_argv"
	# shellcheck disable=SC2154 # ppgt_case_code는 사례 프로세스(case.sh)가 정한다
	PPGT_CASE_CODE=$ppgt_case_code PPGT_EXAMPLE=$ppgt_readme_block PPGT_README_CASE_PATH=$PPGT_CASE_PATH \
		PPGT_ROOT=$PPGT_ROOT "$PPGT_SHELL" -c "$PPGT_README_PREP" "$PPGT_SELF" "$@"
}
