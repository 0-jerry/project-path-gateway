#!/bin/sh
# 테스트 실행기 (research R-12)
#
# 사용법: sh tests/run-legacy.sh [--shell PATH]... [테스트 파일...]
#
# tests/unit, tests/integration, tests/contract 아래 *_test.sh 파일의 test_ 함수를
# 대상 셸마다, 함수마다 새 프로세스와 새 임시 디렉터리에서 실행한다.
# 반환 0은 통과, 77은 건너뜀, 그 외는 실패다.

usage() {
	printf '사용법: sh tests/run-legacy.sh [--shell PATH]... [테스트 파일...]\n' >&2
}

repo_root=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P) || exit 2
shells=
filters=

while [ $# -gt 0 ]; do
	case $1 in
	--shell)
		[ $# -ge 2 ] || {
			usage
			exit 2
		}
		shells="$shells$2
"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		usage
		exit 2
		;;
	*)
		filters="$filters$1
"
		shift
		;;
	esac
done

if [ -z "$shells" ]; then
	shells="/bin/sh
"
	if dash_path=$(command -v dash 2>/dev/null); then
		shells="$shells$dash_path
"
	fi
fi

# 필터가 없거나 파일 경로가 필터 중 하나로 끝나면 참이다. IFS가 개행인 구간에서 호출한다.
matches_filter() {
	[ -z "$filters" ] && return 0
	for f in $filters; do
		case $1 in
		*"$f") return 0 ;;
		esac
	done
	return 1
}

cd "$repo_root" || exit 2

test_files=$(find tests/unit tests/integration tests/contract -name '*_test.sh' 2>/dev/null | LC_ALL=C sort)

passed=0
failed=0
skipped=0
failed_names=

old_ifs=$IFS
IFS='
'
for shell in $shells; do
	for file in $test_files; do
		matches_filter "$file" || continue
		# shellcheck disable=SC2013 # 함수 이름은 공백이 없는 단어다
		for func in $(sed -n 's/^\(test_[a-z0-9_]*\)().*/\1/p' "$file"); do
			tmp=$(mktemp -d "${TMPDIR:-/tmp}/ppg-test.XXXXXX") || exit 2
			log="$tmp.log"
			(
				IFS=$old_ifs
				cd "$tmp" || exit 2
				TEST_TMP=$tmp REPO_ROOT=$repo_root TEST_SHELL=$shell \
					"$shell" -c '. "$REPO_ROOT/tests/lib/assert.sh"; . "$REPO_ROOT/tests/lib/fixture.sh"; . "$REPO_ROOT/$1"; "$2"' \
					_ "$file" "$func"
			) >"$log" 2>&1 </dev/null
			status=$?
			case $status in
			0)
				passed=$((passed + 1))
				printf 'ok    %s %s:%s\n' "$shell" "$file" "$func"
				;;
			77)
				skipped=$((skipped + 1))
				printf 'skip  %s %s:%s (%s)\n' "$shell" "$file" "$func" "$(tail -n 1 "$log")"
				;;
			*)
				failed=$((failed + 1))
				failed_names="$failed_names  $shell $file:$func
"
				printf 'FAIL  %s %s:%s (반환 %s)\n' "$shell" "$file" "$func" "$status"
				sed 's/^/      | /' "$log"
				;;
			esac
			chmod -R u+rwx "$tmp" 2>/dev/null
			rm -rf "$tmp" "$log"
		done
	done
done
IFS=$old_ifs

if [ -n "$failed_names" ]; then
	printf '\n실패한 테스트:\n%s' "$failed_names"
fi
printf '결과: 통과 %s, 실패 %s, 건너뜀 %s (셸: %s)\n' "$passed" "$failed" "$skipped" "$(printf '%s' "$shells" | tr '\n' ' ' | sed 's/ $//')"
[ "$failed" -eq 0 ]
