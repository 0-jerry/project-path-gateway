#!/bin/sh
# 테스트 실행기 (specs/002-dry-run-unit-tests/contracts/runner.md)
#
# 사용법: sh tests/run.sh [--shell PATH]... [필터...]
#
# 필터는 사례 식별자(<사례 파일 경로>:<이름>)의 부분 문자열이며, 여러 개면 하나라도 맞는 사례를 실행한다.
# tests/cases 아래 *.cases 사례 파일을 검증하고, 대상 셸마다·사례마다 tests/harness/case.sh 사례 프로세스를 띄워
# 판정 줄을 출력·집계한다. 파일 시스템 변경은 캡처 공간 하나뿐이며 종료 방식과 무관하게 지운다.
# 반환: 0 실패·데이터 오류 없음, 1 실패 또는 데이터 오류, 2 사용법 오류·캡처 공간 생성 실패·대상 셸 실행 불가

usage() {
	printf '사용법: sh tests/run.sh [--shell PATH]... [필터...]\n'
}

NL='
'
TAB=$(printf '\t')

repo_root=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P) || exit 2
shells=
filters=

while [ $# -gt 0 ]; do
	case $1 in
	--shell)
		if [ $# -lt 2 ] || [ -z "$2" ]; then
			usage >&2
			exit 2
		fi
		shells="$shells$2$NL"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		usage >&2
		exit 2
		;;
	*)
		filters="$filters$1$NL"
		shift
		;;
	esac
done

if [ -z "$shells" ]; then
	shells="/bin/sh$NL"
	if dash_path=$(command -v dash 2>/dev/null); then
		shells="$shells$dash_path$NL"
	fi
fi

old_ifs=$IFS
IFS=$NL
shell_list=
for shell in $shells; do
	if ! "$shell" -c ':' </dev/null >/dev/null 2>&1; then
		printf 'tests/run.sh: 대상 셸을 실행할 수 없습니다: %s\n' "$shell" >&2
		exit 2
	fi
	shell_list="${shell_list:+$shell_list, }$shell"
done
IFS=$old_ifs

cd "$repo_root" || exit 2

cap=$(mktemp -d "${TMPDIR:-/tmp}/ppg-cases.XXXXXX") || {
	printf 'tests/run.sh: 캡처 공간을 만들 수 없습니다\n' >&2
	exit 2
}
trap 'rm -rf "$cap"' EXIT
trap 'rm -rf "$cap"; trap - EXIT; exit 129' HUP
trap 'rm -rf "$cap"; trap - EXIT; exit 130' INT
trap 'rm -rf "$cap"; trap - EXIT; exit 143' TERM

case_files=
if [ -d tests/cases ]; then
	case_files=$(find tests/cases -name '*.cases' -type f | LC_ALL=C sort)
fi

: >"$cap/list"
if [ -n "$case_files" ]; then
	IFS=$NL
	# shellcheck disable=SC2086 # 사례 파일 경로 목록을 줄 단위로 나눈다
	if ! LC_ALL=C awk -v mode=validate -f tests/harness/casefile.awk $case_files >"$cap/list"; then
		printf 'tests/run.sh: 사례 파일 검증 중 하니스 오류가 났습니다\n' >&2
		exit 2
	fi
	IFS=$old_ifs
fi

passed=0
failed=0
data_errors=0
skipped=0
failed_names=
shell_count=0
IFS=$NL
for shell in $shells; do
	shell_count=$((shell_count + 1))
done
IFS=$old_ifs

# 필터가 없거나 사례 식별자가 필터 중 하나를 포함하면 참이다.
matches_filter() {
	[ -n "$filters" ] || return 0
	filter_rest=$filters
	while [ -n "$filter_rest" ]; do
		filter=${filter_rest%%"$NL"*}
		filter_rest=${filter_rest#*"$NL"}
		case $1 in
		*"$filter"*) return 0 ;;
		esac
	done
	return 1
}

# 데이터 오류는 셸 반복 전에 한 번 보고하고 셸 수만큼 집계한다.
while IFS=$TAB read -r kind id cause; do
	[ "$kind" = D ] || continue
	matches_filter "$id" || continue
	printf 'DATA  %s  [%s]\n' "$cause" "$id"
	data_errors=$((data_errors + shell_count))
	IFS=$NL
	for shell in $shells; do
		failed_names="$failed_names  $shell $id$NL"
	done
	IFS=$old_ifs
done <"$cap/list"

# 사례 프로세스 판정 출력의 상세 줄(첫 줄 뒤)을 출력한다.
print_details() {
	case $1 in
	*"$NL"*) printf '%s\n' "${1#*"$NL"}" ;;
	esac
}

# 하니스 오류 상세: 사례 프로세스 stderr를 줄마다 출력한다.
print_harness() {
	printf '      | harness: 기대\n      |   판정 줄\n      | harness: 실제\n'
	harness_lines=0
	while IFS= read -r line || [ -n "$line" ]; do
		printf '      |   %s\n' "$line"
		harness_lines=1
	done <"$1"
	[ "$harness_lines" = 1 ] || printf '      |   (없음)\n'
}

seq=0
IFS=$NL
for shell in $shells; do
	IFS=$old_ifs
	while IFS=$TAB read -r kind file name kind_dir layer target _; do
		[ "$kind" = C ] || continue
		id=$file:$name
		matches_filter "$id" || continue
		seq=$((seq + 1))
		prefix=$cap/$seq
		label="$shell $id [$kind_dir/$layer] $target"
		result=$(PPGT_SHELL=$shell "$shell" tests/harness/case.sh "$repo_root" "$file" "$name" "$prefix" </dev/null 2>"$prefix.harness")
		status=$?
		verdict=${result%%"$NL"*}
		if [ "$status" -ne 0 ] || [ -z "$result" ]; then
			verdict=harness
		fi
		case $verdict in
		ok)
			printf 'ok    %s\n' "$label"
			passed=$((passed + 1))
			;;
		FAIL)
			printf 'FAIL  %s\n' "$label"
			print_details "$result"
			failed=$((failed + 1))
			failed_names="$failed_names  $shell $id$NL"
			;;
		"DATA "*)
			printf 'DATA  %s  [%s]\n' "${verdict#DATA }" "$id"
			data_errors=$((data_errors + 1))
			failed_names="$failed_names  $shell $id$NL"
			;;
		"skip "*)
			printf 'skip  %s (%s)\n' "$label" "${verdict#skip }"
			skipped=$((skipped + 1))
			;;
		*)
			printf 'FAIL  %s\n' "$label"
			print_harness "$prefix.harness"
			failed=$((failed + 1))
			failed_names="$failed_names  $shell $id$NL"
			;;
		esac
		rm -f "$prefix".*
	done <"$cap/list"
	IFS=$NL
done
IFS=$old_ifs

if [ -n "$failed_names" ]; then
	printf '\n실패한 사례:\n%s' "$failed_names"
fi
printf '결과: 통과 %d, 실패 %d, 데이터 오류 %d, 건너뜀 %d (셸: %s)\n' "$passed" "$failed" "$data_errors" "$skipped" "$shell_list"

if [ "$failed" -eq 0 ] && [ "$data_errors" -eq 0 ]; then
	exit 0
fi
exit 1
