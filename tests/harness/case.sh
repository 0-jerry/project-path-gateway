# 사례 프로세스 (specs/002-dry-run-unit-tests/contracts/runner.md 5절)
#
# 사용법: <셸> tests/harness/case.sh <저장소 루트> <사례 파일 경로> <사례 이름> <캡처 파일 접두어>
#
# 사례 하나를 읽고 대상을 서브셸에서 실행한 뒤 판정 줄 하나와 상세를 stdout에 출력한다.
# 대상 실행의 stdout·stderr·fd 9는 <접두어>.stdout, .stderr, .ops로 캡처한다.
# 대상 셸 경로는 환경 변수 PPGT_SHELL로 받는다(없으면 sh).

if [ "$#" -ne 4 ]; then
	printf 'case.sh: 인자는 4개여야 합니다\n' >&2
	exit 2
fi

PPGT_ROOT=$1
PPGT_CASE_FILE=$2
PPGT_CASE_NAME=$3
PPGT_PREFIX=$4
: "${PPGT_SHELL:=sh}"

# 실행기가 중단되어 캡처 공간이 이미 지워졌으면 아무것도 만들지 않고 끝낸다.
[ -d "${PPGT_PREFIX%/*}" ] || exit 0

# shellcheck source=/dev/null
. "$PPGT_ROOT/tests/harness/common.sh"
# shellcheck source=/dev/null
. "$PPGT_ROOT/tests/harness/casefile.sh"
# shellcheck source=/dev/null
. "$PPGT_ROOT/tests/harness/compare.sh"

if ! ppgt_case_code=$(ppgt_casefile_extract "$PPGT_CASE_FILE" "$PPGT_CASE_NAME" "$PPGT_PREFIX"); then
	printf 'case.sh: 사례를 읽지 못했습니다: %s:%s\n' "$PPGT_CASE_FILE" "$PPGT_CASE_NAME" >&2
	exit 1
fi
eval "$ppgt_case_code"

if [ -n "${PPGT_DATA+x}" ]; then
	printf 'DATA %s\n' "$PPGT_DATA"
	exit 0
fi
if [ -n "${PPGT_SKIP+x}" ]; then
	printf 'skip %s\n' "$PPGT_SKIP"
	exit 0
fi

PPGT_ADAPTER_FILE=$PPGT_ROOT/tests/harness/adapters/$PPGT_ADAPTER.sh
if [ ! -f "$PPGT_ADAPTER_FILE" ]; then
	printf 'DATA %s: 어댑터가 아직 없습니다: %s\n' "$PPGT_CASE_FILE" "$PPGT_ADAPTER"
	exit 0
fi

(
	cd / || exit 125
	HOME=/nonexistent/ppg-home
	TMPDIR=/nonexistent/ppg-tmp
	export HOME TMPDIR
	ppgt_case_env
	PPGT_CASE_PATH=${PATH-}
	PATH=$PPGT_ROOT/tests/harness/guard:$PPGT_CASE_PATH
	export PATH
	# shellcheck source=/dev/null
	. "$PPGT_ADAPTER_FILE"
	ppgt_adapter_run
) 9>"$PPGT_PREFIX.ops" >"$PPGT_PREFIX.stdout" 2>"$PPGT_PREFIX.stderr"
ppgt_case_status=$?

ppgt_compare "$PPGT_PREFIX" "$ppgt_case_status"
exit 0
