#!/bin/sh
# 정적 검사 스크립트 (research R-13)
#
# 사용법: sh scripts/lint.sh
#
# 1. 셸 파일 ShellCheck (--shell=sh)
# 2. 라이브러리의 금지 단어 git, exit (대소문자 무시, 단어 경계, 주석 포함)
# 3. 라이브러리·전역 프로그램의 범위 괄호식 [A-Z], [a-z], [0-9]
# 4. 버전 일치 (VERSION 파일, 라이브러리 첫 줄, 전역 프로그램 PPG_VERSION)
# 5. 계층 호출 규칙, 함수 이름·본문 형식, 구획 소유 변수 (plan.md "계층 호출 규칙")

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
	for f in "$lib" "$bin" install.sh uninstall.sh scripts/*.sh tests/run.sh tests/lib/*.sh tests/*/*_test.sh; do
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

# 5. 계층 규칙
check_layers() {
	# $1: 파일, $2: 내부 함수 접두어(lib: project_path_gateway__, bin: ppg__), $3: lib 또는 bin
	awk -v file="$1" -v pre="$2" -v kind="$3" '
	function layer_of(name,   rest) {
		rest = substr(name, length(pre) + 1)
		if (rest ~ /^domain_/) return "domain"
		if (rest ~ /^app_/) return "app"
		if (rest ~ /^infra_/) return "infra"
		if (rest ~ /^if_/) return "if"
		if (rest ~ /^port_/) return "port"
		return "unknown"
	}
	function section_of(line) {
		if (line == "# === 계층: 도메인 ===") return 1
		if (line == "# === 계층: 애플리케이션 ===") return 2
		if (line == "# === 계층: 인프라 ===") return 3
		if (line == "# === 계층: 인터페이스 ===") return 4
		return 0
	}
	function problem(msg) {
		print msg > "/dev/stderr"
		count++
	}
	BEGIN { count = 0; sec = 0; nsec = split("도메인 애플리케이션 인프라 인터페이스", secname, " ") }
	NR == FNR {
		s = section_of($0)
		if (s) { sec = s; next }
		if (match($0, /^[A-Za-z_][A-Za-z0-9_]*\(\)/)) {
			name = substr($0, 1, RLENGTH - 2)
			if (name in defsec && defsec[name] != sec)
				problem(file ":" FNR ": 같은 이름이 두 구획에서 정의됨: " name)
			defsec[name] = sec
			defline[name] = FNR
			body = substr($0, RLENGTH + 1)
			sub(/^[ \t]*/, "", body)
			defbody[name] = substr(body, 1, 1)
		}
		next
	}
	FNR == 1 { sec = 0 }
	{
		s = section_of($0)
		if (s) { sec = s; next }
		line = $0
		if (line ~ /^[ \t]*#/) next
		defname = ""
		if (match(line, /^[A-Za-z_][A-Za-z0-9_]*\(\)/)) {
			defname = substr(line, 1, RLENGTH - 2)
			line = substr(line, RLENGTH + 1)
		}
		while (match(line, pre "[a-z0-9_]+")) {
			call = substr(line, RSTART, RLENGTH)
			line = substr(line, RSTART + RLENGTH)
			if (sec == 0) continue
			cl = layer_of(call)
			ok = 0
			if (cl == "domain") ok = 1
			else if (sec == 2 && (cl == "app" || cl == "port")) ok = 1
			else if (sec == 3 && (cl == "infra" || cl == "port") && defsec[call] == 3) ok = 1
			else if (sec == 4 && (cl == "app" || ((cl == "if" || cl == "port") && defsec[call] == 4))) ok = 1
			if (sec == 1 && cl != "domain") ok = 0
			if (!(call in defsec)) {
				problem(file ":" FNR ": 정의되지 않은 함수 호출: " call)
			} else if (!ok) {
				problem(file ":" FNR ": " secname[sec] " → " call)
			}
		}
		if (kind == "bin") {
			tmp = $0
			while (match(tmp, /PPG_(INFRA|IF)_[A-Z0-9_]*/)) {
				v = substr(tmp, RSTART, RLENGTH)
				tmp = substr(tmp, RSTART + RLENGTH)
				if (v ~ /^PPG_INFRA_/ && sec != 3) problem(file ":" FNR ": 인프라 소유 변수를 구획 밖에서 참조: " v)
				if (v ~ /^PPG_IF_/ && sec != 4) problem(file ":" FNR ": 인터페이스 소유 변수를 구획 밖에서 참조: " v)
			}
		}
	}
	END {
		for (name in defsec) {
			s = defsec[name]
			where = file ":" defline[name]
			if (kind == "lib") {
				if (index(name, "project_path_gateway_") != 1) {
					problem(where ": 함수 이름은 project_path_gateway_로 시작해야 함: " name)
					continue
				}
				if (index(name, pre) != 1) {
					if (name != "project_path_gateway_init" && name != "project_path_gateway_get" && name != "project_path_gateway_verify")
						problem(where ": 공개 함수는 init, get, verify 세 개만 허용: " name)
					else if (s != 4)
						problem(where ": 공개 함수는 인터페이스 구획에 있어야 함: " name)
				}
				if (name != "project_path_gateway_init" && defbody[name] != "(")
					problem(where ": 서브셸 본문 name() ( ... )으로 정의해야 함: " name)
			} else if (index(name, pre) != 1) {
				if (name != "main") problem(where ": 함수 이름은 " pre "로 시작해야 함: " name)
				continue
			}
			if (index(name, pre) != 1) continue
			l = layer_of(name)
			if (l == "domain" && s != 1) problem(where ": 도메인 함수가 도메인 구획 밖에 있음: " name)
			if (l == "app" && s != 2) problem(where ": 애플리케이션 함수가 애플리케이션 구획 밖에 있음: " name)
			if (l == "infra" && s != 3) problem(where ": 인프라 함수가 인프라 구획 밖에 있음: " name)
			if (l == "if" && s != 4) problem(where ": 인터페이스 함수가 인터페이스 구획 밖에 있음: " name)
			if (l == "port" && s != 3 && s != 4) problem(where ": 포트는 인프라 또는 인터페이스 구획에서만 정의: " name)
			if (l == "unknown") problem(where ": 계층 접두어가 없는 내부 함수: " name)
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

if [ "$problems" -gt 0 ]; then
	printf 'lint: 위반 %s건\n' "$problems" >&2
	exit 1
fi
printf 'lint: 통과\n'
