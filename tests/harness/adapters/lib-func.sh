# 어댑터: 라이브러리 내부 함수 (specs/002-dry-run-unit-tests/research.md D-06)
#
# <루트>/lib/project-path-gateway.sh를 불러오고 대체물을 적용한 뒤 target 함수를 arg 토큰 인자로 실행한다.

ppgt_adapter_run() {
	# shellcheck source=/dev/null
	. "$PPGT_ROOT/lib/project-path-gateway.sh"
	ppgt_apply_doubles "$PPGT_ROOT/lib/project-path-gateway.sh" || return 125
	eval "set -- $PPGT_ARGS"
	"$PPGT_TARGET" "$@"
}
