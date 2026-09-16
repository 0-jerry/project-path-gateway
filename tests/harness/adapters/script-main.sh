# 어댑터: 설치·제거 스크립트 main (specs/002-dry-run-unit-tests/research.md D-06)
#
# target 대상(install.sh 또는 uninstall.sh)을 PPG_SOURCE_ONLY=1로 불러오고 대체물을 적용한 뒤 서브셸에서 main을 실행한다.

ppgt_adapter_run() {
	case $PPGT_TARGET in
	install.sh | uninstall.sh) ;;
	*)
		printf 'harness: script-main 대상이 아닙니다: %s\n' "$PPGT_TARGET" >&2
		return 125
		;;
	esac
	# shellcheck disable=SC2034 # 불러오는 스크립트가 읽는다
	PPG_SOURCE_ONLY=1
	# shellcheck source=/dev/null
	. "$PPGT_ROOT/$PPGT_TARGET"
	unset PPG_SOURCE_ONLY
	ppgt_apply_doubles "$PPGT_ROOT/$PPGT_TARGET" || return 125
	eval "set -- $PPGT_ARGS"
	(main "$@")
}
