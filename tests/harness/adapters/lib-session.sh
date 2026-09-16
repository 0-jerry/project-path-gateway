# 어댑터: 라이브러리 공개 함수 호출 세션 (specs/002-dry-run-unit-tests/contracts/doubles.md 4절)
#
# 호출 셸 설정(caller-set, caller-ifs, caller-var, caller-trap)을 적용하고 상태를 기록한 뒤 라이브러리와 대체물을 불러와
# call마다 공개 함수를 실행하고 op returned를 기록한다. 끝에 호출 전 상태와 비교해 다른 항목마다 op changed를 기록하고
# 마지막 호출 반환값으로 끝난다. 호출 셸이 set -e 등으로 중간에 끝나면 그 종료 상태가 그대로 반환값이 된다.
# 하니스 코드는 호출 셸 옵션(set -euf)과 IFS에서도 동작하도록 쓴다.

# 셸 변수 목록에서 하니스·라이브러리 접두어와 셸이 스스로 바꾸는 변수를 뺀 "이름 TAB 값 토큰" 줄
ppgt_session_vars() {
	set | LC_ALL=C "$PPGT_AWK" '
	function flush() {
		if (name == "") return
		if (name ~ /^(PPGT_|ppgt_|PROJECT_PATH_GATEWAY_|BASH|FUNCNAME$|PIPESTATUS$|LINENO$|RANDOM$|SRANDOM$|SECONDS$|EPOCH|SHELLOPTS$|_$|IFS$|OPTIND$|COLUMNS$|LINES$)/) { name = ""; return }
		gsub(/\n/, "\\n", value)
		printf "%s\t%s\n", name, value
		name = ""
	}
	/^[A-Za-z_][A-Za-z0-9_]*=/ {
		flush()
		name = $0; sub(/=.*/, "", name)
		value = $0; sub(/^[^=]*=/, "", value)
		next
	}
	{ value = value "\n" $0 }
	END { flush() }'
}

ppgt_call() {
	ppgt_call_fn=$1
	shift
	"$ppgt_call_fn" "$@"
	PPGT_LAST_STATUS=$?
	ppgt_rec returned "$ppgt_call_fn" "$PPGT_LAST_STATUS"
}

ppgt_adapter_run() {
	PPGT_LAST_STATUS=0
	ppgt_case_caller
	ppgt_before_cwd=$(pwd)
	ppgt_before_options=$(set +o)
	ppgt_before_traps=$(trap)
	ppgt_before_ifs=${IFS-unset}x
	ppgt_before_vars=$(ppgt_session_vars)

	# shellcheck source=/dev/null
	. "$PPGT_ROOT/lib/project-path-gateway.sh"
	ppgt_apply_doubles "$PPGT_ROOT/lib/project-path-gateway.sh" || return 125
	ppgt_case_calls

	if [ "$(pwd)" != "$ppgt_before_cwd" ]; then ppgt_rec changed cwd; fi
	if [ "${IFS-unset}x" != "$ppgt_before_ifs" ]; then ppgt_rec changed ifs; fi
	if [ "$(set +o)" != "$ppgt_before_options" ]; then ppgt_rec changed options; fi
	if [ "$(trap)" != "$ppgt_before_traps" ]; then ppgt_rec changed traps; fi
	ppgt_after_vars=$(ppgt_session_vars)
	if [ "$ppgt_after_vars" != "$ppgt_before_vars" ]; then
		ppgt_changed_names=$(printf '%s\n\001\n%s\n' "$ppgt_before_vars" "$ppgt_after_vars" | LC_ALL=C "$PPGT_AWK" -F '\t' '
		$0 == "\001" { side = 1; next }
		$1 == "" { next }
		side == 0 { before[$1] = $0; next }
		{ after[$1] = $0 }
		END {
			n = 0
			for (k in before) if (!(k in after) || after[k] != before[k]) names[++n] = k
			for (k in after) if (!(k in before)) names[++n] = k
			for (i = 2; i <= n; i++) { t = names[i]; for (j = i - 1; j >= 1 && names[j] > t; j--) names[j + 1] = names[j]; names[j + 1] = t }
			for (i = 1; i <= n; i++) print names[i]
		}')
		ppgt_rest=$ppgt_changed_names
		while [ -n "$ppgt_rest" ]; do
			ppgt_name=${ppgt_rest%%"$PPGT_NL"*}
			case $ppgt_rest in
			*"$PPGT_NL"*) ppgt_rest=${ppgt_rest#*"$PPGT_NL"} ;;
			*) ppgt_rest= ;;
			esac
			ppgt_rec changed "var:$ppgt_name"
		done
	fi
	return "$PPGT_LAST_STATUS"
}
