# 가상 파일 시스템 연산 (specs/002-dry-run-unit-tests/contracts/doubles.md 2절, data-model.md 1.6·2.2)
#
# 반드시 LC_ALL=C로 실행한다. 입력은 모두 환경 변수다(awk -v는 역슬래시를 해석하므로 쓰지 않는다).
#   PPGT_VFS     항목 표. 줄마다 "종류 TAB 경로 토큰 TAB 값 토큰"
#                종류: dir, file(값=내용), link(값=대상), other, deny, readonly, mode(값=모드)
#   PPGT_FAULTS  실패 주입. 줄마다 "작업 종류 TAB 경로 토큰"
#   PPGT_OP      연산 이름(시스템 포트 접미사 또는 init)
#   PPGT_A1, PPGT_A2  포트 인자(바이트 그대로)
#   PPGT_VCWD    가상 작업 디렉터리
#   PPGT_PATHS   command_path가 볼 PATH 값
#
# 출력: 반환값 줄, 작업 기록 줄(없으면 빈 줄), 표 변경 여부 줄(0|1),
#       변경이면 새 표 줄들과 "." 줄, 마지막으로 포트 stdout 바이트와 끝 표지 x

function dec(s,   o, i, c, n) {
	if (s == "\\e") return ""
	o = ""
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (c == "\\" && i < n) {
			i++
			c = substr(s, i, 1)
			if (c == "s") o = o " "
			else if (c == "t") o = o "\t"
			else if (c == "r") o = o "\r"
			else if (c == "n") o = o "\n"
			else o = o c
		} else o = o c
	}
	return o
}

function enc(s,   o, i, c, n) {
	if (s == "") return "\\e"
	o = ""
	n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (c == "\\") o = o "\\\\"
		else if (c == "\t") o = o "\\t"
		else if (c == "\r") o = o "\\r"
		else if (c == "\n") o = o "\\n"
		else if (c == " ") o = o "\\s"
		else o = o c
	}
	return o
}

# 상위 경로. 인자와 결과 모두 "/"로 시작하는 정규화 경로이며 루트는 "/".
function parent(p) {
	if (p == "/") return "/"
	sub(/\/[^\/]*$/, "", p)
	return p == "" ? "/" : p
}

function base(p) {
	sub(/^.*\//, "", p)
	return p
}

# 링크를 풀지 않는 문자열 정규화(실패 주입 경로 비교용)
function norm(p,   n, segs, out, i, k) {
	if (substr(p, 1, 1) != "/") p = cwd "/" p
	n = split(p, segs, "/")
	k = 0
	for (i = 1; i <= n; i++) {
		if (segs[i] == "" || segs[i] == ".") continue
		if (segs[i] == "..") { if (k > 0) k--; continue }
		stack[++k] = segs[i]
	}
	out = ""
	for (i = 1; i <= k; i++) out = out "/" stack[i]
	return out == "" ? "/" : out
}

# 경로를 물리 경로로 푼다. follow가 참이면 마지막 세그먼트 링크도 따라간다.
# 성공하면 rerr가 빈 문자열이고 결과 경로(없는 항목일 수 있음)를 돌려준다.
# 실패 원인 rerr: noent(중간 없음), notdir(중간이 디렉터리 아님), loop(링크 40회 초과), deny(거부 디렉터리 탐색)
function resolve(p, follow,   rest, cur, seg, i, nxt, k, cnt, last, trail, t, r) {
	rerr = ""
	if (p == "") { rerr = "noent"; return "" }
	if (substr(p, 1, 1) != "/") p = cwd "/" p
	trail = (p ~ /\/$/)
	if (trail) follow = 1
	rest = p
	cur = ""
	cnt = 0
	while (1) {
		while (substr(rest, 1, 1) == "/") rest = substr(rest, 2)
		if (rest == "") break
		i = index(rest, "/")
		if (i) { seg = substr(rest, 1, i - 1); rest = substr(rest, i) }
		else { seg = rest; rest = "" }
		last = (rest ~ /^\/*$/)
		if (seg == ".") continue
		if (seg == "..") {
			if (deny[cur == "" ? "/" : cur]) { rerr = "deny"; return "" }
			cur = (cur == "") ? "" : parent(cur)
			if (cur == "/") cur = ""
			continue
		}
		if (deny[cur == "" ? "/" : cur]) { rerr = "deny"; return "" }
		nxt = cur "/" seg
		k = kind[nxt]
		if (k == "link" && (!last || follow)) {
			if (++cnt > 40) { rerr = "loop"; return "" }
			t = val[nxt]
			if (substr(t, 1, 1) == "/") cur = ""
			rest = t rest
			if (rest == "") rest = "."
			continue
		}
		if (last) { cur = nxt; break }
		if (k == "dir") { cur = nxt; continue }
		rerr = (k == "") ? "noent" : "notdir"
		return ""
	}
	r = (cur == "") ? "/" : cur
	if (trail && kind[r] != "dir") { rerr = (kind[r] == "") ? "noent" : "notdir"; return "" }
	return r
}

function faulted(fk, p,   n, lines, i, f, np) {
	np = norm(p)
	n = split(ENVIRON["PPGT_FAULTS"], lines, "\n")
	for (i = 1; i <= n; i++) {
		if (lines[i] == "") continue
		split(lines[i], f, "\t")
		if (f[1] == fk && dec(f[2]) == np) return 1
	}
	return 0
}

function has_children(d,   p) {
	for (p in kind) if (p != "/" && parent(p) == d) return 1
	return 0
}

function drop(p) {
	delete kind[p]; delete val[p]; delete deny[p]; delete ro[p]; delete mode[p]
	changed = 1
}

function readable_file(r) {
	return rerr == "" && kind[r] == "file" && !deny[r]
}

# 새 항목을 만들 수 있는지: 풀기 성공, 상위가 디렉터리, 상위 readonly 아님
function can_create(r) {
	return rerr == "" && kind[parent(r)] == "dir" && !ro[parent(r)]
}

function lines_of(s) {
	if (s != "" && substr(s, length(s)) != "\n") s = s "\n"
	return s
}

function record(k) {
	opline = "op " k
}

function arg_rec(a) {
	opline = opline " " enc(a)
}

function mkdir_p(p,   n, segs, pre, i, r) {
	n = split(norm(p), segs, "/")
	pre = ""
	for (i = 1; i <= n; i++) {
		if (segs[i] == "") continue
		pre = pre "/" segs[i]
		r = resolve(pre, 1)
		if (rerr != "") return 1
		if (kind[r] == "dir") continue
		if (kind[r] != "") return 1
		if (deny[parent(r)] || ro[parent(r)]) return 1
		kind[r] = "dir"
		changed = 1
	}
	return 0
}

function move_entry(rs, rd,   p, np, moved, m, i) {
	m = 0
	for (p in kind) {
		if (p == rs || index(p, rs "/") == 1) moved[++m] = p
	}
	for (i = 1; i <= m; i++) {
		p = moved[i]
		np = rd substr(p, length(rs) + 1)
		nkind[np] = kind[p]; nval[np] = val[p]; ndeny[np] = deny[p]; nro[np] = ro[p]; nmode[np] = mode[p]
		drop(p)
	}
	for (i = 1; i <= m; i++) {
		p = moved[i]
		np = rd substr(p, length(rs) + 1)
		kind[np] = nkind[np]; val[np] = nval[np]
		if (ndeny[np]) deny[np] = 1
		if (nro[np]) ro[np] = 1
		if (nmode[np] != "") mode[np] = nmode[np]
	}
}

function sort_names(arr, n,   i, j, t) {
	for (i = 2; i <= n; i++) {
		t = arr[i]
		for (j = i - 1; j >= 1 && arr[j] > t; j--) arr[j + 1] = arr[j]
		arr[j + 1] = t
	}
}

BEGIN {
	n = split(ENVIRON["PPGT_VFS"], lines, "\n")
	for (i = 1; i <= n; i++) {
		if (lines[i] == "") continue
		m = split(lines[i], f, "\t")
		p = dec(f[2])
		v = (m >= 3) ? dec(f[3]) : ""
		if (f[1] == "deny") deny[p] = 1
		else if (f[1] == "readonly") ro[p] = 1
		else if (f[1] == "mode") mode[p] = v
		else { kind[p] = f[1]; val[p] = v }
	}
	kind["/"] = "dir"
	cwd = ENVIRON["PPGT_VCWD"]
	if (cwd == "") cwd = "/"
	op = ENVIRON["PPGT_OP"]
	a1 = ENVIRON["PPGT_A1"]
	a2 = ENVIRON["PPGT_A2"]
	st = 0
	out = ""
	opline = ""
	changed = 0

	if (op == "init") {
		# 선언 항목의 상위 경로를 디렉터리로 만든다.
		for (p in kind) auto[p] = 1
		for (p in deny) auto[p] = 1
		for (p in ro) auto[p] = 1
		for (p in auto) {
			q = parent(p)
			while (q != "/" && kind[q] == "") { kind[q] = "dir"; q = parent(q) }
		}
		changed = 1
	} else if (op == "is_dir") {
		record("is-dir"); arg_rec(a1)
		r = resolve(a1, 1); st = (rerr == "" && kind[r] == "dir") ? 0 : 1
	} else if (op == "is_file") {
		record("is-file"); arg_rec(a1)
		r = resolve(a1, 1); st = (rerr == "" && kind[r] == "file") ? 0 : 1
	} else if (op == "is_readable") {
		record("is-readable"); arg_rec(a1)
		r = resolve(a1, 1); st = (rerr == "" && kind[r] != "" && !deny[r]) ? 0 : 1
	} else if (op == "exists") {
		record("exists"); arg_rec(a1)
		r = resolve(a1, 1); st = (rerr == "" && kind[r] != "") ? 0 : 1
	} else if (op == "is_writable") {
		# 파일에 붙인 readonly는 이 판정에만 쓴다(기능 004 research R-08).
		record("is-writable"); arg_rec(a1)
		r = resolve(a1, 1); st = (rerr == "" && kind[r] != "" && !deny[r] && !ro[r]) ? 0 : 1
	} else if (op == "is_link") {
		record("is-link"); arg_rec(a1)
		r = resolve(a1, 0); st = (rerr == "" && kind[r] == "link") ? 0 : 1
	} else if (op == "physical_dir") {
		record("physical-dir"); arg_rec(a1)
		r = resolve(a1, 1)
		if (rerr == "" && kind[r] == "dir" && !deny[r]) out = r "x"
		else st = 1
	} else if (op == "readlink") {
		record("readlink"); arg_rec(a1)
		r = resolve(a1, 0)
		if (rerr == "" && kind[r] == "link") out = val[r] "x"
		else st = 1
	} else if (op == "read_lines") {
		record("read-lines"); arg_rec(a1)
		r = resolve(a1, 1)
		if (readable_file(r)) out = lines_of(val[r])
		else st = 1
	} else if (op == "read_file") {
		record("read-file"); arg_rec(a1)
		r = resolve(a1, 1)
		if (readable_file(r)) out = val[r] "x"
		else st = 1
	} else if (op == "command_path") {
		record("command-path"); arg_rec(a1)
		st = 1
		if (index(a1, "/")) {
			r = resolve(a1, 1)
			if (rerr == "" && kind[r] == "file") { out = a1 "x"; st = 0 }
		} else {
			m = split(ENVIRON["PPGT_PATHS"], dirs, ":")
			for (i = 1; i <= m; i++) {
				d = (dirs[i] == "") ? "." : dirs[i]
				r = resolve(d "/" a1, 1)
				if (rerr == "" && kind[r] == "file") { out = d "/" a1 "x"; st = 0; break }
			}
		}
	} else if (op == "list_prefix") {
		record("list-prefix"); arg_rec(a1); arg_rec(a2)
		r = resolve(a1, 1)
		if (rerr == "" && kind[r] == "dir" && !deny[r]) {
			m = 0
			for (p in kind) {
				if (p == "/" || parent(p) != r) continue
				nm = base(p)
				if (substr(nm, 1, length(a2)) == a2) names[++m] = nm
			}
			sort_names(names, m)
			for (i = 1; i <= m; i++) out = out names[i] "\n"
		}
	} else if (op == "mkdir") {
		record("mkdir"); arg_rec(a1)
		r = resolve(a1, 0)
		if (faulted("mkdir", a1) || !can_create(r) || kind[r] != "") st = 1
		else { kind[r] = "dir"; changed = 1 }
	} else if (op == "mkdir_p") {
		record("mkdir-p"); arg_rec(a1)
		st = faulted("mkdir-p", a1) ? 1 : mkdir_p(a1)
	} else if (op == "rmdir") {
		record("rmdir"); arg_rec(a1)
		r = resolve(a1, 0)
		if (faulted("rmdir", a1) || rerr != "" || r == "/" || kind[r] != "dir" || has_children(r) || ro[parent(r)]) st = 1
		else drop(r)
	} else if (op == "remove") {
		record("remove"); arg_rec(a1)
		r = resolve(a1, 0)
		if (faulted("remove", a1) || rerr == "deny" || rerr == "notdir") st = 1
		else if (rerr != "" || kind[r] == "") st = 0
		else if (kind[r] == "dir" || ro[parent(r)]) st = 1
		else drop(r)
	} else if (op == "write_text") {
		record("write"); arg_rec(a1); arg_rec(a2)
		r = resolve(a1, 1)
		if (faulted("write", a1) || !can_create(r) || kind[r] == "dir" || deny[r]) st = 1
		else { kind[r] = "file"; val[r] = a2; changed = 1 }
	} else if (op == "copy_to") {
		record("copy"); arg_rec(a1); arg_rec(a2)
		rs = resolve(a1, 1)
		if (!readable_file(rs)) st = 1
		else {
			content = val[rs]
			r = resolve(a2, 1)
			if (faulted("copy", a2) || !can_create(r) || kind[r] == "dir" || deny[r]) st = 1
			else { kind[r] = "file"; val[r] = content; changed = 1 }
		}
	} else if (op == "copy_preserve") {
		record("copy-preserve"); arg_rec(a1); arg_rec(a2)
		rs = resolve(a1, 1)
		if (!readable_file(rs)) st = 1
		else {
			content = val[rs]
			srcmode = mode[rs]
			r = resolve(a2, 1)
			if (faulted("copy-preserve", a2) || !can_create(r) || kind[r] == "dir" || deny[r]) st = 1
			else {
				kind[r] = "file"; val[r] = content
				if (srcmode != "") mode[r] = srcmode
				changed = 1
			}
		}
	} else if (op == "link") {
		record("link"); arg_rec(a1); arg_rec(a2)
		rs = resolve(a1, 1)
		if (rerr != "" || kind[rs] != "file") st = 1
		else {
			content = val[rs]
			r = resolve(a2, 0)
			if (faulted("link", a2) || !can_create(r) || kind[r] != "") st = 1
			else { kind[r] = "file"; val[r] = content; changed = 1 }
		}
	} else if (op == "move") {
		record("move"); arg_rec(a1); arg_rec(a2)
		rs = resolve(a1, 0)
		if (rerr != "" || kind[rs] == "" || ro[parent(rs)]) st = 1
		else {
			r = resolve(a2, 0)
			if (rerr == "" && kind[r] == "dir" && kind[rs] != "dir") r = r "/" base(rs)
			if (faulted("move", a2) || !can_create(r) || kind[r] == "dir") st = 1
			else if (r != rs) { if (kind[r] != "") drop(r); move_entry(rs, r); changed = 1 }
		}
	} else if (op == "chmod") {
		record("chmod"); arg_rec(a1); arg_rec(a2)
		r = resolve(a2, 1)
		if (faulted("chmod", a2) || rerr != "" || kind[r] == "") st = 1
		else { mode[r] = a1; changed = 1 }
	} else if (op == "cd") {
		# readme-example cd: a2가 P이면 물리 경로. 기록은 호출 쪽에서 한다.
		r = resolve(a1, 1)
		if (rerr == "" && kind[r] == "dir" && !deny[r]) out = (a2 == "P" ? r : norm(a1)) "x"
		else st = 1
	} else {
		st = 125
	}

	printf "%d\n%s\n%d\n", st, opline, changed
	if (changed) {
		for (p in kind) printf "%s\t%s\t%s\n", kind[p], enc(p), enc(val[p])
		for (p in deny) if (deny[p]) printf "deny\t%s\t\\e\n", enc(p)
		for (p in ro) if (ro[p]) printf "readonly\t%s\t\\e\n", enc(p)
		for (p in mode) if (mode[p] != "") printf "mode\t%s\t%s\n", enc(p), enc(mode[p])
		printf ".\n"
	}
	printf "%sx", out
}
