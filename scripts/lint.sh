#!/bin/sh
# 정적 검사 스크립트 (research R-13)
#
# 사용법: sh scripts/lint.sh
#
# 1. 셸 파일 ShellCheck (--shell=sh)
# 2. 라이브러리의 금지 단어 git, exit (대소문자 무시, 단어 경계, 주석 포함)
# 3. 라이브러리·전역 프로그램의 범위 괄호식 [A-Z], [a-z], [0-9]
# 4. 버전 일치 (VERSION 파일, 라이브러리 첫 줄, 전역 프로그램 PPG_VERSION)
# 5. 계층 규칙 D-1~D-6과 L-0: 계층 호출, 포트 목록, 출력 문구 위치, 애플리케이션 문자열 조작,
#    함수 이름·본문 형식, 구획 소유 변수 (기능 005 contracts/lint-rules.md)
#    대상: 라이브러리, 전역 프로그램, 설치·제거 스크립트. 시스템 포트(__sys_*)는 인프라 구획 전용
# 6. 환경 접근 위치 (002 contracts/system-ports.md 3절): 시스템 포트 본문 밖의 파일 리다이렉션(E-1),
#    파일 검사 연산자(E-2), 파일·신호 명령(E-3), $$·$0(E-4), for 목록 글로브(E-5),
#    파이프라인·명령 치환 안의 변경 시스템 포트 호출
# 7. 추적 대조표(tests/traceability.md)의 사례 식별자·수동 확인 절 참조
# 8. lint 자체 확인: tests/lint/fixtures/*.sh 위반 예시(D-1~D-6)를 5절 검사가 모두 잡는지 확인

repo_root=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P) || exit 2
cd "$repo_root" || exit 2

lib=lib/project-path-gateway.sh
bin=bin/project-path-gateway
problems=0

report() {
	printf '%s\n' "$1" >&2
	problems=$((problems + 1))
}

# 1. ShellCheck
if command -v shellcheck >/dev/null 2>&1; then
	files=
	for f in "$lib" "$bin" install.sh uninstall.sh scripts/*.sh tests/run.sh tests/harness/*.sh tests/harness/adapters/*.sh tests/harness/guard/* tests/harness/guard/.guard.sh; do
		[ -f "$f" ] && files="$files $f"
	done
	if [ -n "$files" ]; then
		# shellcheck disable=SC2086 # 파일 이름에 공백이 없는 저장소 내부 경로 목록이다
		if ! shellcheck --shell=sh $files >&2; then
			report "shellcheck: 경고가 있습니다"
		fi
	fi
else
	report "shellcheck: 설치되어 있지 않습니다"
fi

# 2. 금지 단어
if [ -f "$lib" ]; then
	if grep -n -i -w -E 'git|exit' "$lib" >&2; then
		report "$lib: 금지 단어(git, exit)가 있습니다"
	fi
fi

# 3. 범위 괄호식
for f in "$lib" "$bin"; do
	[ -f "$f" ] || continue
	if grep -n -E '\[!?[^]]*(A-Z|a-z|0-9)' "$f" >&2; then
		report "$f: 범위 괄호식은 로캘에 따라 결과가 달라 쓸 수 없습니다 (research R-04)"
	fi
done

# 4. 버전 일치
version=$(cat VERSION 2>/dev/null)
if [ -z "$version" ]; then
	report "VERSION: 파일이 없거나 비어 있습니다"
else
	if [ -f "$lib" ]; then
		first=$(sed -n '1p' "$lib")
		[ "$first" = "# project-path-gateway $version" ] ||
			report "$lib:1: 첫 줄이 '# project-path-gateway $version'이 아닙니다: $first"
	fi
	if [ -f "$bin" ]; then
		bin_version=$(sed -n 's/^PPG_VERSION=//p' "$bin")
		[ "$bin_version" = "$version" ] ||
			report "$bin: PPG_VERSION($bin_version)이 VERSION($version)과 다릅니다"
	fi
fi

# 5. 계층 규칙 (기능 005 contracts/lint-rules.md 1절). 위반 한 건마다 "<파일>:<줄>: [<ID>] <설명>: <이름 또는 내용>"을 쓴다.
#    D-1 도메인 → 다른 계층, D-2 애플리케이션 → 금지 대상·목록 밖 포트, D-3 인프라 → 바깥 계층,
#    D-4 인터페이스 밖 출력 문구, D-5 애플리케이션 문자열 조작, D-6 포트 목록 불일치, L-0 그 밖의 기존 규칙
check_layers() {
	# $1: 파일, $2: 내부 함수 접두어(lib: project_path_gateway__, 그 밖: ppg__), $3: lib, bin, script
	LC_ALL=C awk -v file="$1" -v pre="$2" -v kind="$3" '
	function layer_of(name,   rest) {
		rest = substr(name, length(pre) + 1)
		if (rest ~ /^domain_/) return "domain"
		if (rest ~ /^app_/) return "app"
		if (rest ~ /^infra_/) return "infra"
		if (rest ~ /^if_/) return "if"
		if (rest ~ /^port_/) return "port"
		if (rest ~ /^out_/) return "out"
		if (rest ~ /^sys_/) return "sys"
		return "unknown"
	}
	function section_of(line) {
		if (line == "# === 계층: 도메인 ===") return 1
		if (line == "# === 계층: 애플리케이션 ===") return 2
		if (line == "# === 계층: 인프라 ===") return 3
		if (line == "# === 계층: 인터페이스 ===") return 4
		return 0
	}
	function problem(line, id, msg) {
		print file ":" line ": [" id "] " msg > "/dev/stderr"
		count++
	}
	# 포트 목록 줄(# 입력 포트: ..., # 출력 포트: ...)의 이름을 모은다 (contracts/ports.md 1절).
	function collect_ports(line, want,   n, i, tok) {
		if (sec != 2) { problem(FNR, "D-6", "포트 목록은 애플리케이션 구획에만 둔다: " line); return }
		n = split(line, tok, /[ \t]+/)
		if (n < 4) { problem(FNR, "D-6", "포트 목록 형식 오류: " line); return }
		for (i = 4; i <= n; i++) {
			if (index(tok[i], pre) != 1 || layer_of(tok[i]) != want || tok[i] !~ /^[A-Za-z0-9_]+$/) {
				problem(FNR, "D-6", "포트 목록 형식 오류: " tok[i])
				continue
			}
			listed[tok[i]] = 1
			listline[tok[i]] = FNR
		}
	}
	BEGIN { count = 0; sec = 0; nsec = split("도메인 애플리케이션 인프라 인터페이스", secname, " ") }
	NR == FNR {
		s = section_of($0)
		if (s) { sec = s; next }
		if ($0 ~ /^# 입력 포트:/) { collect_ports($0, "port"); next }
		if ($0 ~ /^# 출력 포트:/) { collect_ports($0, "out"); next }
		if (match($0, /^[A-Za-z_][A-Za-z0-9_]*\(\)/)) {
			name = substr($0, 1, RLENGTH - 2)
			if (name in defsec && defsec[name] != sec)
				problem(FNR, "L-0", "같은 이름이 두 구획에서 정의됨: " name)
			defsec[name] = sec
			defline[name] = FNR
			body = substr($0, RLENGTH + 1)
			sub(/^[ \t]*/, "", body)
			defbody[name] = substr(body, 1, 1)
		}
		next
	}
	FNR == 1 { sec = 0; curfn = "" }
	{
		s = section_of($0)
		if (s) { sec = s; next }
		line = $0
		if (line ~ /^[ \t]*#/) next
		if (match(line, /^[A-Za-z_][A-Za-z0-9_]*\(\)/)) {
			curfn = substr(line, 1, RLENGTH - 2)
			line = substr(line, RLENGTH + 1)
		}
		if (sec >= 1 && sec <= 3) {
			if ($0 ~ /(^|[^0-9])1?>&2/) problem(FNR, "D-4", "인터페이스 구획 밖에서 표준 오류로 출력: " curfn)
			if ($0 ~ /project-path-gateway:/) problem(FNR, "D-4", "인터페이스 구획 밖에 출력 문구: " curfn)
		}
		if (sec == 2) {
			tmp = $0
			while (match(tmp, /\$\{[A-Za-z_][A-Za-z0-9_]*(#|%)/)) {
				rest = substr(tmp, RSTART + RLENGTH)
				expr = substr(tmp, RSTART, RLENGTH)
				tmp = rest
				if (expr ~ /%$/ && rest ~ /^x\}/) continue
				problem(FNR, "D-5", "애플리케이션 구획의 문자열 조작: " expr)
			}
		}
		while (match(line, pre "[a-z0-9_]+")) {
			call = substr(line, RSTART, RLENGTH)
			line = substr(line, RSTART + RLENGTH)
			if (sec == 0) continue
			if (!(call in defsec)) {
				problem(FNR, "L-0", "정의되지 않은 함수 호출: " call)
				continue
			}
			cl = layer_of(call)
			if (index(curfn, pre) == 1 && layer_of(curfn) == "sys" && call != curfn) {
				problem(FNR, "D-3", "시스템 포트 본문에서 내부 함수 호출: " call)
				continue
			}
			if (cl == "domain") continue
			if (sec == 1) {
				problem(FNR, "D-1", "도메인 → " call)
			} else if (sec == 2) {
				if (cl == "app") continue
				if ((cl == "port" || cl == "out") && (call in listed)) continue
				if (cl == "port" || cl == "out") problem(FNR, "D-2", "애플리케이션 → 포트 목록에 없는 포트: " call)
				else problem(FNR, "D-2", "애플리케이션 → " call)
			} else if (sec == 3) {
				if ((cl == "infra" || cl == "port" || cl == "sys") && defsec[call] == 3) continue
				if (cl == "app" || cl == "if" || cl == "out") problem(FNR, "D-3", "인프라 → " call)
				else problem(FNR, "L-0", "인프라 → " call)
			} else if (sec == 4) {
				if (cl == "app") continue
				if ((cl == "if" || cl == "out") && defsec[call] == 4) continue
				problem(FNR, "L-0", "인터페이스 → " call)
			}
		}
		if (kind == "bin") {
			tmp = $0
			while (match(tmp, /PPG_(INFRA|IF)_[A-Z0-9_]*/)) {
				v = substr(tmp, RSTART, RLENGTH)
				tmp = substr(tmp, RSTART + RLENGTH)
				if (v ~ /^PPG_INFRA_/ && sec != 3) problem(FNR, "L-0", "인프라 소유 변수를 구획 밖에서 참조: " v)
				if (v ~ /^PPG_IF_/ && sec != 4) problem(FNR, "L-0", "인터페이스 소유 변수를 구획 밖에서 참조: " v)
			}
		}
	}
	END {
		for (name in listed)
			if (!(name in defsec)) problem(listline[name], "D-6", "포트 목록의 이름이 정의되지 않음: " name)
		for (name in defsec) {
			s = defsec[name]
			where = defline[name]
			if (kind == "lib") {
				if (index(name, "project_path_gateway_") != 1) {
					problem(where, "L-0", "함수 이름은 project_path_gateway_로 시작해야 함: " name)
					continue
				}
				if (index(name, pre) != 1) {
					if (name != "project_path_gateway_init" && name != "project_path_gateway_get" && name != "project_path_gateway_verify" &&
						name != "project_path_gateway_add" && name != "project_path_gateway_update")
						problem(where, "L-0", "공개 함수는 init, get, verify, add, update 다섯 개만 허용: " name)
					else if (s != 4)
						problem(where, "L-0", "공개 함수는 인터페이스 구획에 있어야 함: " name)
				}
				if (name != "project_path_gateway_init" && defbody[name] != "(")
					problem(where, "L-0", "서브셸 본문 name() ( ... )으로 정의해야 함: " name)
			} else if (index(name, pre) != 1) {
				if (name != "main") problem(where, "L-0", "함수 이름은 " pre "로 시작해야 함: " name)
				continue
			}
			if (index(name, pre) != 1) continue
			l = layer_of(name)
			if (l == "domain" && s != 1) problem(where, "L-0", "도메인 함수가 도메인 구획 밖에 있음: " name)
			if (l == "app" && s != 2) problem(where, "L-0", "애플리케이션 함수가 애플리케이션 구획 밖에 있음: " name)
			if (l == "infra" && s != 3) problem(where, "L-0", "인프라 함수가 인프라 구획 밖에 있음: " name)
			if (l == "if" && s != 4) problem(where, "L-0", "인터페이스 함수가 인터페이스 구획 밖에 있음: " name)
			if (l == "port" && s != 3) problem(where, "D-6", "입력 포트는 인프라 구획에서만 정의: " name)
			if (l == "out" && s != 4) problem(where, "D-6", "출력 포트는 인터페이스 구획에서만 정의: " name)
			if ((l == "port" || l == "out") && !(name in listed)) problem(where, "D-6", "포트 목록에 없는 포트: " name)
			if (l == "sys" && s != 3) problem(where, "L-0", "시스템 포트가 인프라 구획 밖에 있음: " name)
			if (l == "unknown") problem(where, "L-0", "계층 접두어가 없는 내부 함수: " name)
		}
		exit (count > 0)
	}
	' "$1" "$1"
}

if [ -f "$lib" ]; then
	check_layers "$lib" project_path_gateway__ lib || report "$lib: 계층 규칙 위반이 있습니다"
fi
if [ -f "$bin" ]; then
	check_layers "$bin" ppg__ bin || report "$bin: 계층 규칙 위반이 있습니다"
fi
for f in install.sh uninstall.sh; do
	[ -f "$f" ] || continue
	check_layers "$f" ppg__ script || report "$f: 계층 규칙 위반이 있습니다"
done

# 6. 환경 접근 위치
check_env_access() {
	LC_ALL=C awk -v file="$1" '
	function problem(msg) {
		print file ":" FNR ": " msg > "/dev/stderr"
		count++
	}
	BEGIN { count = 0; curfn = ""; sq = sprintf("%c", 39) }
	{
		line = $0
		if (match(line, /^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*[{(]/)) {
			curfn = substr(line, 1, index(line, "(") - 1)
			next
		}
		if (line ~ /^[})]$/) { curfn = ""; next }
		if (line ~ /^[ \t]*#/) next
		if (curfn ~ /__sys_/) next
		# 작은따옴표 문자열을 지우고(E-4 검사용), 큰따옴표 문자열을 "" 로 줄인다(나머지 검사용).
		nosq = line
		gsub(sq "[^" sq "]*" sq, "", nosq)
		sub(/[ \t]#.*$/, "", nosq)
		code = nosq
		gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
		rest = code
		while (match(rest, /(>>|>|<)/)) {
			after = substr(rest, RSTART + RLENGTH)
			if (after !~ /^&/ && after !~ /^\/dev\/null/) {
				problem("E-1 시스템 포트 밖 파일 리다이렉션")
				break
			}
			rest = after
		}
		if (code ~ /(\[|test)[ \t]+(![ \t]+)?-[defhLprswx][ \t]/)
			problem("E-2 시스템 포트 밖 파일 검사")
		if (code ~ /(^|[;&|({!]|\$\(|[ \t](if|then|do|else|elif|while|until))[ \t]*(cd|readlink|mkdir|rmdir|rm|mv|ln|cp|cat|chmod|trap|kill)([ \t]|$)/ ||
			code ~ /command[ \t]+-v/ || code ~ /pwd[ \t]+-P/)
			problem("E-3 시스템 포트 밖 파일·신호 명령")
		if (nosq ~ /\$\$|\$0|\$\{0/)
			problem("E-4 시스템 포트 밖 $$ 또는 $0")
		if (code ~ /^[ \t]*for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t].*[*?[]/)
			problem("E-5 시스템 포트 밖 for 목록 글로브")
		if (code ~ /__sys_(mkdir|mkdir_p|rmdir|remove|write_text|copy_to|copy_preserve|link|move|chmod|trap)([ \t]|$)/) {
			pipe = code
			gsub(/\|\|/, "", pipe)
			if (pipe ~ /\|/ || code ~ /\$\(/)
				problem("파이프라인·명령 치환 안의 변경 시스템 포트 호출")
		}
	}
	END { exit (count > 0) }
	' "$1"
}

for f in "$lib" "$bin" install.sh uninstall.sh; do
	[ -f "$f" ] || continue
	check_env_access "$f" || report "$f: 시스템 포트 밖 환경 접근이 있습니다"
done

# 7. 추적 대조표 참조 (002 research D-09 5절): 표의 사례 식별자가 사례 파일의 case 줄로 있고,
#    사례 열이 비어 있지 않으며, 수동 확인 절 번호가 tests/manual-checks.md의 "## <번호>." 제목으로 있어야 한다.
check_traceability() {
	LC_ALL=C awk '
	FNR == 1 { file_index++ }
	file_index == 1 {
		if ($0 ~ /^## [0-9]+\./) { n = $2; sub(/\..*/, "", n); section[n] = 1 }
		next
	}
	!/^\|/ { case_col = 0; manual_col = 0; next }
	/^\| *-/ { next }
	{
		cols = split($0, cell, "|")
		if (case_col == 0) {
			for (i = 2; i < cols; i++) {
				h = cell[i]; gsub(/^ +| +$/, "", h)
				if (h == "사례") case_col = i
				if (h == "수동 확인") manual_col = i
			}
			next
		}
		row = cell[2]; gsub(/^ +| +$/, "", row)
		ids = 0
		rest = cell[case_col]
		while (match(rest, /`[^`]*`/)) {
			id = substr(rest, RSTART + 1, RLENGTH - 2)
			rest = substr(rest, RSTART + RLENGTH)
			ids++
			k = index(id, ".cases:")
			if (id !~ /^tests\/cases\// || k == 0) { printf "%s:%d: 사례 식별자 형식이 아닙니다: %s\n", FILENAME, FNR, id; count++; continue }
			path = substr(id, 1, k + 5); name = substr(id, k + 7)
			if (!(path in loaded)) {
				loaded[path] = 1
				while ((getline line < path) > 0) if (line ~ /^case /) have[path ":" substr(line, 6)] = 1
				close(path)
			}
			if (!(id in have)) { printf "%s:%d: 사례가 없습니다: %s\n", FILENAME, FNR, id; count++ }
		}
		if (ids == 0) { printf "%s:%d: 사례 열이 비어 있습니다: %s\n", FILENAME, FNR, row; count++ }
		refs = ""
		if (manual_col > 0) { m = cell[manual_col]; gsub(/[^0-9]+/, " ", m); refs = refs " " m }
		rest = $0
		while (match(rest, /수동 확인 [0-9]+/)) {
			refs = refs " " substr(rest, RSTART + length("수동 확인 "), RLENGTH - length("수동 확인 "))
			rest = substr(rest, RSTART + RLENGTH)
		}
		nr = split(refs, ref, " ")
		for (i = 1; i <= nr; i++) {
			if (!(ref[i] in section)) { printf "%s:%d: 수동 확인 절이 없습니다: %s\n", FILENAME, FNR, ref[i]; count++ }
		}
	}
	END { exit (count > 0) }
	' tests/manual-checks.md tests/traceability.md
}

if [ -f tests/traceability.md ]; then
	check_traceability >&2 || report "tests/traceability.md: 추적 대조표 참조 오류가 있습니다"
fi

# 8. lint 자체 확인 (기능 005 contracts/lint-rules.md 2절): tests/lint/fixtures/*.sh 위반 예시마다 5절 검사가 실패하고
#    머리 주석 "# lint-fixture: kind=<lib|bin|script> expect=<ID>"의 규칙 ID를 보고해야 한다.
lint_tmp=$(mktemp "${TMPDIR:-/tmp}/ppg-lint.XXXXXX") || exit 2
for f in tests/lint/fixtures/*.sh; do
	[ -f "$f" ] || continue
	fixture_kind=$(sed -n 's/^# lint-fixture: kind=\([a-z]*\) expect=.*$/\1/p' "$f")
	fixture_expect=$(sed -n 's/^# lint-fixture: kind=[a-z]* expect=\([A-Z0-9-]*\)$/\1/p' "$f")
	case $fixture_kind in
	lib) fixture_pre=project_path_gateway__ ;;
	bin | script) fixture_pre=ppg__ ;;
	*)
		report "$f: lint 자체 확인 실패: 머리 주석 형식 오류"
		continue
		;;
	esac
	if [ -z "$fixture_expect" ]; then
		report "$f: lint 자체 확인 실패: 머리 주석 형식 오류"
		continue
	fi
	if check_layers "$f" "$fixture_pre" "$fixture_kind" 2>"$lint_tmp"; then
		report "lint 자체 확인 실패: $f (위반을 찾지 못함)"
	elif ! grep -F -q "[$fixture_expect]" "$lint_tmp"; then
		cat "$lint_tmp" >&2
		report "lint 자체 확인 실패: $f ([$fixture_expect] 보고 없음)"
	fi
done
rm -f "$lint_tmp"

if [ "$problems" -gt 0 ]; then
	printf 'lint: 위반 %s건\n' "$problems" >&2
	exit 1
fi
printf 'lint: 통과\n'
