# 사례 판정 (specs/002-dry-run-unit-tests/contracts/runner.md 2절, contracts/doubles.md 1절)
#
# 기대값 파일은 사례 추출(casefile.awk extract)이 캡처 공간에 쓴다:
#   <접두어>.want-stdout, .want-stderr, .want-ops
# 실제값은 대상 실행 캡처다: <접두어>.stdout, .stderr, .ops

# 조회 종류 작업 기록(ops changes에서 비교하지 않음)
PPGT_READ_KINDS='is-dir is-file is-readable is-writable exists is-link physical-dir readlink read-lines read-file self-path command-path pid list-prefix cd pwd'

# 바이트 파일을 사례 파일 이스케이프 표기 줄로 출력한다. $1: 필드 이름(out, err), $2: 파일
ppgt_render_bytes() {
	LC_ALL=C "$PPGT_AWK" -v field="$1" 'BEGIN { RS = "\001"; all = "" }
	{ all = all $0 }
	function esc(s,   o, i, c) {
		o = ""
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c == "\\") o = o "\\\\"
			else if (c == "\t") o = o "\\t"
			else if (c == "\r") o = o "\\r"
			else o = o c
		}
		return o
	}
	END {
		if (all == "") { print "      |   (없음)"; exit }
		n = split(all, parts, "\n")
		for (i = 1; i < n; i++) {
			if (parts[i] == "") printf "      |   %s\n", field
			else printf "      |   %s %s\n", field, esc(parts[i])
		}
		if (parts[n] != "") printf "      |   %s-raw %s\n", field, esc(parts[n])
	}' "$2"
}

# 작업 기록 파일을 줄 그대로 출력한다.
ppgt_render_lines() {
	LC_ALL=C "$PPGT_AWK" 'BEGIN { n = 0 } { n++; printf "      |   %s\n", $0 } END { if (n == 0) print "      |   (없음)" }' "$1"
}

# 실제 작업 기록에서 비교 대상 줄만 남긴다. $1: 실제 기록, $2: 결과 파일
ppgt_filter_ops() {
	LC_ALL=C "$PPGT_AWK" -v mode="$PPGT_OPS" -v kinds="$PPGT_READ_KINDS" 'BEGIN { n = split(kinds, k, " "); for (i = 1; i <= n; i++) read[k[i]] = 1 }
	$2 == "violation" || $2 == "unmatched-stub" { next }
	mode == "changes" && ($2 in read) { next }
	{ print }' "$1" >"$2"
}

# 위반 기록(violation, unmatched-stub)만 뽑는다. $1: 실제 기록, $2: 결과 파일
ppgt_violation_ops() {
	LC_ALL=C "$PPGT_AWK" '$2 == "violation" || $2 == "unmatched-stub" { print }' "$1" >"$2"
}

# 판정해 stdout에 ok 또는 FAIL과 상세 블록을 출력한다. $1: 캡처 접두어, $2: 실제 반환값
ppgt_compare() {
	ppgt_cmp_p=$1
	ppgt_cmp_fail=0
	ppgt_cmp_out=
	if [ "$2" != "$PPGT_WANT_STATUS" ]; then
		ppgt_cmp_fail=1
		ppgt_cmp_out="$ppgt_cmp_out      | status: 기대$PPGT_NL      |   $PPGT_WANT_STATUS$PPGT_NL      | status: 실제$PPGT_NL      |   $2$PPGT_NL"
	fi
	for ppgt_cmp_item in stdout stderr; do
		if ! cmp -s "$ppgt_cmp_p.want-$ppgt_cmp_item" "$ppgt_cmp_p.$ppgt_cmp_item"; then
			ppgt_cmp_fail=1
			case $ppgt_cmp_item in
			stdout) ppgt_cmp_field=out ;;
			*) ppgt_cmp_field=err ;;
			esac
			ppgt_cmp_want=$(ppgt_render_bytes "$ppgt_cmp_field" "$ppgt_cmp_p.want-$ppgt_cmp_item")
			ppgt_cmp_got=$(ppgt_render_bytes "$ppgt_cmp_field" "$ppgt_cmp_p.$ppgt_cmp_item")
			ppgt_cmp_out="$ppgt_cmp_out      | $ppgt_cmp_item: 기대$PPGT_NL$ppgt_cmp_want$PPGT_NL      | $ppgt_cmp_item: 실제$PPGT_NL$ppgt_cmp_got$PPGT_NL"
		fi
	done
	ppgt_filter_ops "$ppgt_cmp_p.ops" "$ppgt_cmp_p.ops-cmp"
	if ! cmp -s "$ppgt_cmp_p.want-ops" "$ppgt_cmp_p.ops-cmp"; then
		ppgt_cmp_fail=1
		ppgt_cmp_want=$(ppgt_render_lines "$ppgt_cmp_p.want-ops")
		ppgt_cmp_got=$(ppgt_render_lines "$ppgt_cmp_p.ops-cmp")
		ppgt_cmp_out="$ppgt_cmp_out      | ops: 기대$PPGT_NL$ppgt_cmp_want$PPGT_NL      | ops: 실제$PPGT_NL$ppgt_cmp_got$PPGT_NL"
	fi
	ppgt_violation_ops "$ppgt_cmp_p.ops" "$ppgt_cmp_p.violation"
	if [ -s "$ppgt_cmp_p.violation" ]; then
		ppgt_cmp_fail=1
		ppgt_cmp_got=$(ppgt_render_lines "$ppgt_cmp_p.violation")
		ppgt_cmp_out="$ppgt_cmp_out      | violation: 기대$PPGT_NL      |   (없음)$PPGT_NL      | violation: 실제$PPGT_NL$ppgt_cmp_got$PPGT_NL"
	fi
	if [ "$ppgt_cmp_fail" = 0 ]; then
		printf 'ok\n'
	else
		printf 'FAIL\n%s' "$ppgt_cmp_out"
	fi
}
