# 사례 파일 읽기 (specs/002-dry-run-unit-tests/contracts/case-file.md)
#
# 파싱·검증·해독은 tests/harness/casefile.awk가 바이트 단위(LC_ALL=C)로 한다.

# 사례 파일 목록을 검증한다. 출력 형식은 casefile.awk 머리 주석의 validate 절.
ppgt_casefile_validate() {
	LC_ALL=C awk -v mode=validate -f "$PPGT_ROOT/tests/harness/casefile.awk" "$@"
}

# 사례 하나를 읽어 준비 코드를 출력하고 기대값 파일을 쓴다. $1: 파일, $2: 이름, $3: 캡처 접두어
ppgt_casefile_extract() {
	LC_ALL=C awk -v mode=extract -v case_name_arg="$2" -v prefix="$3" -f "$PPGT_ROOT/tests/harness/casefile.awk" "$1"
}
