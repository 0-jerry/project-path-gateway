# 어댑터: 전역 프로그램 main (specs/002-dry-run-unit-tests/research.md D-06)
#
# PPG_SOURCE_ONLY=1로 <루트>/bin/project-path-gateway를 불러오고 대체물을 적용한 뒤 서브셸에서 main을 arg 인자로 실행한다.
# main의 exit와 발화용 EXIT trap은 그 서브셸 안에서 끝난다.

ppgt_adapter_run() {
	# shellcheck disable=SC2034 # 불러오는 전역 프로그램이 읽는다
	PPG_SOURCE_ONLY=1
	# shellcheck source=/dev/null
	. "$PPGT_ROOT/bin/project-path-gateway"
	unset PPG_SOURCE_ONLY
	ppgt_apply_doubles "$PPGT_ROOT/bin/project-path-gateway" || return 125
	eval "set -- $PPGT_ARGS"
	(main "$@")
}
