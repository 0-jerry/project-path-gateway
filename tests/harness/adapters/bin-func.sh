# 어댑터: 전역 프로그램 내부 함수 (specs/002-dry-run-unit-tests/research.md D-06)
#
# PPG_SOURCE_ONLY=1로 <루트>/bin/project-path-gateway를 불러오고(main 미실행) 대체물을 적용한 뒤
# target 함수를 arg 토큰 인자로 실행한다.

ppgt_adapter_run() {
	# shellcheck disable=SC2034 # 불러오는 전역 프로그램이 읽는다
	PPG_SOURCE_ONLY=1
	# shellcheck source=/dev/null
	. "$PPGT_ROOT/bin/project-path-gateway"
	unset PPG_SOURCE_ONLY
	ppgt_apply_doubles "$PPGT_ROOT/bin/project-path-gateway" || return 125
	eval "set -- $PPGT_ARGS"
	"$PPGT_TARGET" "$@"
}
