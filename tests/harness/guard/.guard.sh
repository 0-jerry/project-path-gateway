# dry-run 가드 공통 본문 (specs/002-dry-run-unit-tests/contracts/doubles.md 5절)
#
# 가드 실행 파일이 source한다. $0은 가드 실행 파일 경로, 인자는 가로챈 명령의 인자다.
# 파일 시스템에 접근하지 않고 fd 9가 열려 있을 때만 기록한다.

ppgt_guard_name=${0##*/}
ppgt_guard_line="op violation $ppgt_guard_name"
for ppgt_guard_arg in "$@"; do
	case $ppgt_guard_arg in
	'') ppgt_guard_tok='\e' ;;
	*)
		ppgt_guard_tok=$(printf '%s' "$ppgt_guard_arg" | LC_ALL=C awk 'BEGIN { RS = "\001" }
		{
			o = ""
			for (i = 1; i <= length($0); i++) {
				c = substr($0, i, 1)
				if (c == "\\") o = o "\\\\"
				else if (c == "\t") o = o "\\t"
				else if (c == "\r") o = o "\\r"
				else if (c == "\n") o = o "\\n"
				else if (c == " ") o = o "\\s"
				else o = o c
			}
			printf "%s", o
		}')
		;;
	esac
	ppgt_guard_line="$ppgt_guard_line $ppgt_guard_tok"
done
{ printf '%s\n' "$ppgt_guard_line" >&9; } 2>/dev/null
printf 'dry-run 가드: %s\n' "$ppgt_guard_name" >&2
exit 125
