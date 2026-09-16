# 어댑터: 설치·제거 스크립트 내부 함수 (specs/002-dry-run-unit-tests/research.md D-06)
#
# target script-func <install.sh|uninstall.sh> <함수 이름>. 스크립트를 PPG_SOURCE_ONLY=1로 불러오고 대체물을 적용한 뒤
# 함수를 arg 인자로 실행한다.

ppgt_adapter_run() {
	case $PPGT_TARGET_FILE in
	install.sh | uninstall.sh) ;;
	*)
		printf 'harness: script-func 대상 파일이 아닙니다: %s\n' "$PPGT_TARGET_FILE" >&2
		return 125
		;;
	esac
	# shellcheck disable=SC2034 # 불러오는 스크립트가 읽는다
	PPG_SOURCE_ONLY=1
	# shellcheck source=/dev/null
	. "$PPGT_ROOT/$PPGT_TARGET_FILE"
	unset PPG_SOURCE_ONLY
	ppgt_apply_doubles "$PPGT_ROOT/$PPGT_TARGET_FILE" || return 125
	eval "set -- $PPGT_ARGS"
	"$PPGT_TARGET" "$@"
}
