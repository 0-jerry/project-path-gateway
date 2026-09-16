# 사례 파일 파서 (specs/002-dry-run-unit-tests/contracts/case-file.md, data-model.md 1절)
#
# 반드시 LC_ALL=C로 실행한다(바이트 단위 처리).
#
# mode=validate  인자: 사례 파일 목록
#   출력(TAB 구분):
#     D <사례 식별자> <파일>:<줄>: <원인>     데이터 오류 한 건
#     C <파일> <이름> <구분> <layer> <대상 이름> <skip 여부 0|1>   유효한 사례
# mode=extract   인자: 사례 파일 하나
#   -v case_name_arg=이름 -v prefix=캡처 접두어
#   출력: 사례를 준비하는 셸 코드(eval용). 데이터 오류면 PPGT_DATA 대입만 출력한다.
#   부수 효과: <prefix>.want-stdout, .want-stderr, .want-ops 파일에 기대값을 쓴다.

function reset_file() {
	nhead = 0
	ncase = 0
	header_err = ""
	header_err_line = 0
	in_case = 0
	last_field = ""
	last_fs_kind = ""
	dir = file_dir(cur_file)
}

function file_dir(f,   n, parts) {
	n = split(f, parts, "/")
	if (n >= 2) return parts[n - 1]
	return ""
}

function err(line, cause) {
	if (in_case) {
		if (!(cur_loc in case_err)) case_err[cur_loc] = cur_file ":" line ": " cause
	} else if (header_err == "") {
		header_err = cur_file ":" line ": " cause
	}
}

# 이스케이프 검사. 허용하지 않은 조합이 있으면 그 조합, 없으면 빈 문자열.
function bad_escape(v, token,   i, c, n) {
	n = length(v)
	for (i = 1; i <= n; i++) {
		c = substr(v, i, 1)
		if (c != "\\") continue
		if (i == n) return "\\"
		c = substr(v, i + 1, 1)
		if (c == "\\" || c == "t" || c == "r" || c == "n") { i++; continue }
		if (token && c == "s") { i++; continue }
		if (token && c == "e" && v == "\\e") { i++; continue }
		return "\\" c
	}
	return ""
}

function decode(v,   out, i, c, n) {
	if (v == "\\e") return ""
	out = ""
	n = length(v)
	for (i = 1; i <= n; i++) {
		c = substr(v, i, 1)
		if (c != "\\") { out = out c; continue }
		c = substr(v, ++i, 1)
		if (c == "t") out = out "\t"
		else if (c == "r") out = out "\r"
		else if (c == "n") out = out "\n"
		else if (c == "s") out = out " "
		else out = out c
	}
	return out
}

function shq(v) {
	gsub(SQ, SQ "\\" SQ SQ, v)
	return SQ v SQ
}

function is_int(v) { return v ~ /^(0|[1-9][0-9]*)$/ }

function normalized_abs(p) {
	if (p == "/") return 1
	if (p !~ /^\//) return 0
	if (p ~ /\/$/) return 0
	if (p ~ /\/\//) return 0
	if (p ~ /(^|\/)\.\.?(\/|$)/) return 0
	return 1
}

BEGIN {
	# 작업 기록 종류별 인자 토큰 개수(contracts/doubles.md). 끝이 +이면 그 수 이상.
	split("is-dir:1 is-file:1 is-readable:1 is-writable:1 exists:1 is-link:1 physical-dir:1 readlink:1 read-lines:1 read-file:1 self-path:0 command-path:1 pid:0 list-prefix:2 cd:1 pwd:0 " \
		"mkdir:1 mkdir-p:1 rmdir:1 remove:1 write:2 copy:2 copy-preserve:2 link:2 move:2 chmod:2 trap:2 port:1+ returned:2 changed:1 source:1", a, " ")
	for (k in a) { split(a[k], opkv, ":"); op_argc[opkv[1]] = opkv[2] }
	split("is-dir is-file is-readable is-writable exists is-link physical-dir readlink read-lines read-file self-path command-path pid list-prefix cd pwd", a, " ")
	for (k in a) read_kind[a[k]] = 1
	SQ = sprintf("%c", 39)
	TAB = "\t"
	CR = sprintf("%c", 13)
	split("target layer doubles ops", a, " "); for (k in a) header_only[a[k]] = 1
	split("status op out out-raw err err-raw skip", a, " "); for (k in a) case_only[a[k]] = 1
	split("arg call env unset-env cwd self pid fs fault interrupt stub caller-set caller-ifs caller-var caller-trap status op target layer doubles ops case", a, " ")
	for (k in a) token_field[a[k]] = 1
	split("content content-raw stub-out stub-out-raw stub-err out out-raw err err-raw skip", a, " ")
	for (k in a) text_field[a[k]] = 1
	split("lib-func lib-session bin-func bin-main script-func script-main readme-example", a, " ")
	for (k in a) adapters[a[k]] = 1
	split("is-dir is-file is-readable is-writable exists is-link physical-dir readlink read-lines read-file self-path command-path pid list-prefix cd pwd", a, " ")
	for (k in a) read_ops[a[k]] = 1
	nerr = 0
	nres = 0
	prev_file = ""
}

FNR == 1 {
	if (prev_file != "") finish_file()
	prev_file = FILENAME
	cur_file = FILENAME
	reset_file()
}

{
	line = $0
	if (line == "" || substr(line, 1, 1) == "#") next
	if (index(line, TAB) || index(line, CR)) { err(FNR, "날 TAB 또는 CR 바이트가 있습니다"); next }
	if (substr(line, 1, 1) == " ") { err(FNR, "토큰 구분 공백이 잘못되었습니다"); next }
	sp = index(line, " ")
	if (sp) { name = substr(line, 1, sp - 1); value = substr(line, sp + 1); has_value = 1 }
	else { name = line; value = ""; has_value = 0 }

	if (name == "case") {
		in_case = 1
		ncase++
		cname = value
		cur_id = cur_file ":" cname
		cur_loc = cur_file ":" FNR
		if (cname !~ /^[a-z0-9_-]+$/) {
			cur_id = cur_file ":" FNR
			err(FNR, "허용하지 않는 값입니다: case " value)
		}
		case_id[ncase] = cur_id
		case_name[ncase] = cname
		case_line[ncase] = FNR
		case_nf[ncase] = 0
		case_has_status[ncase] = 0
		case_skip[ncase] = 0
		if (cname in first_seen) {
			dup[cur_loc] = first_seen[cname]
			if (!(first_seen[cname] in dup)) dup[first_seen[cname]] = cur_loc
		} else if (cname ~ /^[a-z0-9_-]+$/) {
			first_seen[cname] = cur_loc
		}
		last_field = "case"
		next
	}
	if (!(name in token_field) && !(name in text_field)) { err(FNR, "알 수 없는 필드입니다: " name); next }
	if (in_case && (name in header_only)) { err(FNR, "이 위치에 올 수 없는 필드입니다: " name); next }
	if (!in_case && (name in case_only)) { err(FNR, "이 위치에 올 수 없는 필드입니다: " name); next }
	if ((name == "content" || name == "content-raw") && !(last_field == "fs-file" || last_field == "content")) {
		err(FNR, "이 위치에 올 수 없는 필드입니다: " name); next
	}
	if (name ~ /^stub-/ && !(last_field == "stub" || last_field == "stub-x")) {
		err(FNR, "이 위치에 올 수 없는 필드입니다: " name); next
	}

	if (name in text_field) {
		b = bad_escape(value, 0)
		if (b != "") { err(FNR, "허용하지 않는 이스케이프입니다: " b); next }
		ntok = 0
	} else {
		if (!has_value || value == "") { err(FNR, "토큰 개수가 잘못되었습니다: " name); next }
		if (value ~ /  / || value ~ /^ / || value ~ / $/) { err(FNR, "토큰 구분 공백이 잘못되었습니다"); next }
		ntok = split(value, tok, " ")
		bad = 0
		for (t = 1; t <= ntok; t++) {
			b = bad_escape(tok[t], 1)
			if (b != "") { err(FNR, "허용하지 않는 이스케이프입니다: " b); bad = 1; break }
		}
		if (bad) next
		if (!check_tokens(name, ntok)) next
	}

	# 필드 저장
	if (in_case) {
		n = ++case_nf[ncase]
		cf_name[ncase, n] = name
		cf_value[ncase, n] = value
		cf_line[ncase, n] = FNR
		if (name == "status") case_has_status[ncase] = 1
		if (name == "skip") case_skip[ncase] = 1
	} else {
		n = ++nhead
		hf_name[n] = name
		hf_value[n] = value
		hf_line[n] = FNR
	}
	if (name == "fs") last_field = (tok[1] == "file") ? "fs-file" : "fs"
	else if (name == "content" || name == "content-raw") last_field = "content"
	else if (name == "stub") last_field = "stub"
	else if (name ~ /^stub-/) last_field = "stub-x"
	else last_field = name
}

# 필드별 토큰 개수·값 검사. 문제가 있으면 오류를 기록하고 0.
function check_tokens(name, n,   v1, ok, want) {
	v1 = decode(tok[1])
	if (name == "target") {
		if (!(tok[1] in adapters)) { err(FNR, "허용하지 않는 값입니다: target " tok[1]); return 0 }
		if ((tok[1] == "script-func" && n != 3) || (tok[1] != "script-func" && n != 2)) { err(FNR, "토큰 개수가 잘못되었습니다: target"); return 0 }
		return 1
	}
	if (name == "layer" || name == "doubles" || name == "ops" || name == "arg" || name == "unset-env" || name == "cwd" ||
		name == "self" || name == "pid" || name == "caller-set" || name == "caller-ifs" || name == "status") {
		if (n != 1) { err(FNR, "토큰 개수가 잘못되었습니다: " name); return 0 }
	}
	if (name == "env" || name == "fault" || name == "interrupt" || name == "caller-var" || name == "caller-trap") {
		if (n != 2) { err(FNR, "토큰 개수가 잘못되었습니다: " name); return 0 }
	}
	if ((name == "call" || name == "op") && n < 1) { err(FNR, "토큰 개수가 잘못되었습니다: " name); return 0 }
	if (name == "stub" && n < 2) { err(FNR, "토큰 개수가 잘못되었습니다: " name); return 0 }
	if (name == "layer" && tok[1] !~ /^(domain|app|infra|api)$/) { err(FNR, "허용하지 않는 값입니다: layer " tok[1]); return 0 }
	if (name == "doubles" && tok[1] !~ /^(none|ports|system)$/) { err(FNR, "허용하지 않는 값입니다: doubles " tok[1]); return 0 }
	if (name == "ops" && tok[1] !~ /^(all|changes)$/) { err(FNR, "허용하지 않는 값입니다: ops " tok[1]); return 0 }
	if (name == "status" && !(is_int(tok[1]) && tok[1] + 0 <= 255)) { err(FNR, "허용하지 않는 값입니다: status " tok[1]); return 0 }
	if (name == "stub" && !(is_int(tok[2]) && tok[2] + 0 <= 255)) { err(FNR, "허용하지 않는 값입니다: stub " tok[2]); return 0 }
	if (name == "pid" && !is_int(tok[1])) { err(FNR, "허용하지 않는 값입니다: pid " tok[1]); return 0 }
	if ((name == "env" || name == "unset-env" || name == "caller-var") && v1 !~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
		err(FNR, "허용하지 않는 값입니다: " name " " tok[1]); return 0
	}
	if (name == "cwd" && !normalized_abs(v1)) { err(FNR, "허용하지 않는 값입니다: cwd " tok[1]); return 0 }
	if (name == "interrupt") {
		if (tok[1] !~ /^(INT|TERM|HUP)$/ || !(is_int(tok[2]) && tok[2] + 0 >= 1)) { err(FNR, "허용하지 않는 값입니다: interrupt " value); return 0 }
	}
	if (name == "fault" && tok[1] !~ /^(mkdir|mkdir-p|rmdir|remove|write|copy|copy-preserve|link|move|chmod)$/) {
		err(FNR, "허용하지 않는 값입니다: fault " tok[1]); return 0
	}
	if (name == "op" && (tok[1] == "violation" || tok[1] == "unmatched-stub")) {
		err(FNR, "기대값에 쓸 수 없는 작업입니다: " tok[1]); return 0
	}
	if (name == "op") {
		if (!(tok[1] in op_argc)) { err(FNR, "허용하지 않는 값입니다: op " tok[1]); return 0 }
		want = op_argc[tok[1]]
		if ((want ~ /\+$/ && n - 1 < want + 0) || (want !~ /\+$/ && n - 1 != want + 0)) { err(FNR, "토큰 개수가 잘못되었습니다: op " tok[1]); return 0 }
	}
	if (name == "fs") {
		ok = 0
		if (tok[1] ~ /^(dir|file|other|deny|readonly)$/ && n == 2) ok = 1
		if (tok[1] == "link" && n == 3) ok = 1
		if (!ok) {
			if (tok[1] ~ /^(dir|file|other|deny|readonly|link)$/) err(FNR, "토큰 개수가 잘못되었습니다: fs")
			else err(FNR, "허용하지 않는 값입니다: fs " tok[1])
			return 0
		}
		if (!normalized_abs(decode(tok[2]))) { err(FNR, "허용하지 않는 값입니다: fs " tok[2]); return 0 }
	}
	return 1
}

# 머리말과 사례를 합쳐 검사한다. 사례 하나의 첫 오류 원인을 돌려준다(없으면 빈 문자열).
function check_combined(c,   i, layer, adapter, doubles, opsmode, has_target, fname, allowed, p, parent, k, kinds, where) {
	layer = ""; adapter = ""; doubles = ""; opsmode = ""; has_target = 0
	for (i = 1; i <= nhead; i++) {
		if (hf_name[i] == "target") { has_target = 1; split(hf_value[i], tt, " "); adapter = tt[1] }
		if (hf_name[i] == "layer") layer = hf_value[i]
		if (hf_name[i] == "doubles") doubles = hf_value[i]
		if (hf_name[i] == "ops") opsmode = hf_value[i]
	}
	where = cur_file ":" (nhead ? hf_line[1] : 1) ": "
	if (!has_target) return where "필수 필드가 없습니다: target"
	if (layer == "") return where "필수 필드가 없습니다: layer"
	if (!((dir == "unit" && layer == "domain") || (dir == "integration" && (layer == "app" || layer == "infra")) || (dir == "contract" && layer == "api")))
		return where "구분 디렉터리와 layer가 맞지 않습니다"
	allowed = (layer == "domain") ? "none" : (layer == "app") ? "ports" : "system"
	if (doubles != "" && doubles != allowed) return where "허용하지 않는 값입니다: doubles " doubles
	if (layer == "domain" && opsmode != "") return where "이 위치에 올 수 없는 필드입니다: ops"
	if (opsmode == "") opsmode = (layer == "api") ? "changes" : "all"
	if (opsmode == "changes") {
		for (i = 1; i <= case_nf[c]; i++) {
			if (cf_name[c, i] != "op") continue
			split(cf_value[c, i], tt, " ")
			if (tt[1] in read_kind) return cur_file ":" cf_line[c, i] ": ops changes에서 비교하지 않는 작업입니다: " tt[1]
		}
	}
	doubles = allowed
	if (!case_has_status[c]) return cur_file ":" case_line[c] ": 필수 필드가 없습니다: status"
	# 입력 필드와 어댑터 조합
	for (i = 1; i <= nhead + case_nf[c]; i++) {
		if (i <= nhead) { fname = hf_name[i]; where = cur_file ":" hf_line[i] ": " }
		else { fname = cf_name[c, i - nhead]; where = cur_file ":" cf_line[c, i - nhead] ": " }
		if (fname == "arg" && adapter !~ /^(lib-func|bin-func|script-func|bin-main|script-main)$/) return where "어댑터가 쓰지 않는 입력입니다: arg"
		if (fname == "call" && adapter !~ /^(lib-session|readme-example)$/) return where "어댑터가 쓰지 않는 입력입니다: call"
		if (fname ~ /^caller-/ && adapter != "lib-session") return where "어댑터가 쓰지 않는 입력입니다: " fname
		if ((fname == "cwd" || fname == "pid" || fname == "fs" || fname ~ /^content/ || fname == "fault" || fname == "interrupt") && doubles != "system")
			return where "어댑터가 쓰지 않는 입력입니다: " fname
		if (fname == "self" && doubles != "system") return where "어댑터가 쓰지 않는 입력입니다: self"
		if (fname ~ /^stub/ && doubles != "ports") return where "어댑터가 쓰지 않는 입력입니다: " fname
		if (fname == "op" && layer == "domain") return where "이 위치에 올 수 없는 필드입니다: op"
	}
	if (adapter == "readme-example") {
		p = 0
		for (i = 1; i <= nhead; i++) if (hf_name[i] == "self") p = 1
		for (i = 1; i <= case_nf[c]; i++) if (cf_name[c, i] == "self") p = 1
		if (!p) return cur_file ":" case_line[c] ": 필수 필드가 없습니다: self"
	}
	# 가상 파일 시스템 상위 경로 종류 충돌
	delete kinds
	for (i = 1; i <= nhead + case_nf[c]; i++) {
		if (i <= nhead) { fname = hf_name[i]; v = hf_value[i] } else { fname = cf_name[c, i - nhead]; v = cf_value[c, i - nhead] }
		if (fname != "fs") continue
		split(v, tt, " ")
		if (tt[1] == "file" || tt[1] == "link" || tt[1] == "other") kinds[decode(tt[2])] = tt[1]
	}
	for (i = 1; i <= nhead + case_nf[c]; i++) {
		if (i <= nhead) { fname = hf_name[i]; v = hf_value[i]; where = cur_file ":" hf_line[i] ": " } else { fname = cf_name[c, i - nhead]; v = cf_value[c, i - nhead]; where = cur_file ":" cf_line[c, i - nhead] ": " }
		if (fname != "fs") continue
		split(v, tt, " ")
		p = decode(tt[2])
		parent = p
		while (sub(/\/[^\/]*$/, "", parent) && parent != "") {
			if (parent in kinds) return where "허용하지 않는 값입니다: fs " tt[2] " (상위 경로가 " kinds[parent] ")"
		}
	}
	return ""
}

function finish_file(   c, cause, id, tname, tt2, i, layer_v) {
	tname = ""
	layer_v = ""
	for (i = 1; i <= nhead; i++) {
		if (hf_name[i] == "target") {
			split(hf_value[i], tt2, " ")
			tname = decode(tt2[2])
			if (tt2[1] == "script-func") tname = tname ":" decode(tt2[3])
		}
		if (hf_name[i] == "layer") layer_v = hf_value[i]
	}
	for (c = 1; c <= ncase; c++) {
		id = case_id[c]
		cause = ""
		if (header_err != "") cause = header_err
		else if ((cur_file ":" case_line[c]) in case_err) cause = case_err[cur_file ":" case_line[c]]
		else cause = check_combined(c)
		if (mode == "validate") {
			nres++
			res_id[nres] = id
			res_cause[nres] = cause
			res_line[nres] = cur_file ":" case_line[c]
			res_name[nres] = case_name[c]
			res_meta[nres] = cur_file "\t" case_name[c] "\t" dir "\t" layer_v "\t" tname "\t" case_skip[c]
		} else if (mode == "extract" && case_name[c] == case_name_arg && !found) {
			found = 1
			if (cause == "") emit_case(c)
			else printf "PPGT_DATA=%s\n", shq(cause)
		}
	}
}

END {
	if (prev_file != "") finish_file()
	if (mode == "extract" && !found) printf "PPGT_DATA=%s\n", shq("사례를 찾지 못했습니다: " case_name_arg)
	for (k = 1; k <= nres; k++) {
		cause = res_cause[k]
		if (cause == "" && (res_line[k] in dup))
			cause = res_line[k] ": 사례 이름이 중복되었습니다: " res_name[k] " (다른 위치: " dup[res_line[k]] ")"
		if (cause != "") printf "D\t%s\t%s\n", res_id[k], cause
		else printf "C\t%s\n", res_meta[k]
	}
}

# ---- extract ----

function emit_case(c,   i, fname, v, n, t, layer, adapter, doubles, opsmode, redefined, lists, out_file, err_file, ops_file, skipv) {
	adapter = ""; layer = ""; doubles = ""; opsmode = ""
	delete redefined
	for (i = 1; i <= case_nf[c]; i++) if (cf_name[c, i] == "fs") { split(cf_value[c, i], tt, " "); if (tt[1] ~ /^(dir|file|link|other)$/) redefined[tt[2]] = 1 }
	for (i = 1; i <= nhead; i++) {
		if (hf_name[i] == "target") {
			n = split(hf_value[i], tt, " ")
			adapter = tt[1]
			printf "PPGT_ADAPTER=%s\n", shq(adapter)
			if (n == 3) { printf "PPGT_TARGET_FILE=%s\nPPGT_TARGET=%s\n", shq(decode(tt[2])), shq(decode(tt[3])) }
			else printf "PPGT_TARGET=%s\n", shq(decode(tt[2]))
		}
		if (hf_name[i] == "layer") layer = hf_value[i]
		if (hf_name[i] == "doubles") doubles = hf_value[i]
		if (hf_name[i] == "ops") opsmode = hf_value[i]
	}
	if (doubles == "") doubles = (layer == "domain") ? "none" : (layer == "app") ? "ports" : "system"
	if (opsmode == "") opsmode = (layer == "domain") ? "none" : (layer == "api") ? "changes" : "all"
	printf "PPGT_LAYER=%s\nPPGT_DOUBLES=%s\nPPGT_OPS=%s\nPPGT_KIND=%s\n", shq(layer), shq(doubles), shq(opsmode), shq(dir)

	args = ""; envs = ""; fsc = ""; stubs = ""; calls = ""; callers = ""; faults = ""
	singles_cwd = ""; singles_self = ""; singles_pid = ""; interrupt = ""
	pending = ""
	skipv = ""
	out_file = prefix ".want-stdout"; err_file = prefix ".want-stderr"; ops_file = prefix ".want-ops"
	printf "" > out_file; printf "" > err_file; printf "" > ops_file
	for (i = 1; i <= nhead + case_nf[c]; i++) {
		if (i <= nhead) { fname = hf_name[i]; v = hf_value[i]; from_case = 0 }
		else { fname = cf_name[c, i - nhead]; v = cf_value[c, i - nhead]; from_case = 1 }
		if (fname in token_field) n = split(v, tt, " ")
		if (fname == "arg") args = args " " shq(decode(tt[1]))
		else if (fname == "env") envs = envs "\n\texport " decode(tt[1]) "=" shq(decode(tt[2]))
		else if (fname == "unset-env") envs = envs "\n\tunset " decode(tt[1])
		else if (fname == "cwd") singles_cwd = decode(tt[1])
		else if (fname == "self") singles_self = decode(tt[1])
		else if (fname == "pid") singles_pid = tt[1]
		else if (fname == "fault") faults = faults "\n\tppgt_fault " shq(tt[1]) " " shq(decode(tt[2]))
		else if (fname == "interrupt") interrupt = "PPGT_INT_SIG=" tt[1] "\nPPGT_INT_N=" tt[2] "\n"
		else if (fname == "fs") {
			flush_pending()
			if (!from_case && (tt[2] in redefined) && tt[1] ~ /^(dir|file|link|other)$/) { skipping_content = 1; continue }
			skipping_content = 0
			if (tt[1] == "file") { pending = "\n\tppgt_vfs_add file " shq(decode(tt[2])) " "; pending_content = ""; has_pending = 1 }
			else if (tt[1] == "link") fsc = fsc "\n\tppgt_vfs_add link " shq(decode(tt[2])) " " shq(decode(tt[3]))
			else fsc = fsc "\n\tppgt_vfs_add " tt[1] " " shq(decode(tt[2]))
		}
		else if (fname == "content") { if (!skipping_content) pending_content = pending_content decode(v) "\n" }
		else if (fname == "content-raw") { if (!skipping_content) pending_content = pending_content decode(v) }
		else if (fname == "stub") {
			flush_stub()
			stub_fn = decode(tt[1]); stub_ret = tt[2]; stub_out = ""; stub_err = ""; stub_args = ""
			for (t = 3; t <= n; t++) stub_args = stub_args " " shq(decode(tt[t]))
			has_stub = 1
		}
		else if (fname == "stub-out") stub_out = stub_out decode(v) "\n"
		else if (fname == "stub-out-raw") stub_out = stub_out decode(v)
		else if (fname == "stub-err") stub_err = stub_err decode(v) "\n"
		else if (fname == "call") {
			calls = calls "\n\tppgt_call"
			for (t = 1; t <= n; t++) calls = calls " " shq(decode(tt[t]))
		}
		else if (fname == "caller-set") callers = callers "\n\tset " shq(decode(tt[1]))
		else if (fname == "caller-ifs") callers = callers "\n\tIFS=" shq(decode(tt[1]))
		else if (fname == "caller-var") callers = callers "\n\t" decode(tt[1]) "=" shq(decode(tt[2]))
		else if (fname == "caller-trap") callers = callers "\n\ttrap " shq(decode(tt[2])) " " shq(decode(tt[1]))
		else if (fname == "status") printf "PPGT_WANT_STATUS=%s\n", tt[1]
		else if (fname == "out") printf "%s\n", decode(v) > out_file
		else if (fname == "out-raw") printf "%s", decode(v) > out_file
		else if (fname == "err") printf "%s\n", decode(v) > err_file
		else if (fname == "err-raw") printf "%s", decode(v) > err_file
		else if (fname == "op") printf "op %s\n", v > ops_file
		else if (fname == "skip") skipv = decode(v)
	}
	flush_pending()
	flush_stub()
	close(out_file); close(err_file); close(ops_file)
	printf "PPGT_ARGS=%s\n", shq(args)
	printf "PPGT_CWD=%s\n", shq(singles_cwd == "" ? "/" : singles_cwd)
	printf "PPGT_SELF=%s\nPPGT_HAS_SELF=%s\n", shq(singles_self), (singles_self == "" ? "0" : "1")
	printf "PPGT_PID=%s\n", shq(singles_pid == "" ? "4242" : singles_pid)
	printf "%s", interrupt
	if (skipv != "" || case_skip[c]) printf "PPGT_SKIP=%s\n", shq(skipv == "" ? "-" : skipv)
	printf "ppgt_case_env() {\n\t:%s\n}\n", envs
	printf "ppgt_case_fs() {\n\t:%s%s\n}\n", fsc, faults
	printf "ppgt_case_stubs() {\n\t:%s\n}\n", stubs
	printf "ppgt_case_calls() {\n\t:%s\n}\n", calls
	printf "ppgt_case_caller() {\n\t:%s\n}\n", callers
}

function flush_pending() {
	if (has_pending) { fsc = fsc pending shq(pending_content); has_pending = 0; pending = "" }
}

function flush_stub() {
	if (has_stub) {
		stubs = stubs "\n\tppgt_stub " shq(stub_fn) " " stub_ret " " shq(stub_out) " " shq(stub_err) stub_args
		has_stub = 0
	}
}
