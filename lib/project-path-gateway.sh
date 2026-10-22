# project-path-gateway 2.1.0
#
# 프로젝트 경로 게이트웨이 라이브러리.
# 호출 셸에서 이 파일을 불러온(source) 뒤 공개 함수를 사용한다.
#
#   project_path_gateway_init [START_DIR]         루트 표식 파일을 찾아 루트를 한 번 계산한다
#   project_path_gateway_verify [REPORT_FILE]     등록된 모든 경로의 존재, 루트 내부 여부, 실제 종류를 확인한다
#   project_path_gateway_dir KEY                  디렉터리 키의 경로를 루트 기준 절대경로로 출력한다
#   project_path_gateway_file KEY                 파일 키의 경로를 루트 기준 절대경로로 출력한다
#   project_path_gateway_add_dir KEY PATH         디렉터리 데이터 파일 끝에 새 키와 경로를 등록한다(키가 있으면 오류)
#   project_path_gateway_add_file KEY PATH        파일 데이터 파일 끝에 새 키와 경로를 등록한다(키가 있으면 오류)
#   project_path_gateway_update_dir KEY PATH      디렉터리 키의 경로를 바꾼다(키가 없거나 파일 키이면 오류)
#   project_path_gateway_update_file KEY PATH     파일 키의 경로를 바꾼다(키가 없거나 디렉터리 키이면 오류)
#   project_path_gateway_add_list LIST            KEY=경로 목록(파일, -이면 표준 입력)을 경로 모양에 맞는 데이터 파일에 한꺼번에 등록한다
#   project_path_gateway_scan                     루트 아래 셸 스크립트에 직접 적힌 경로를 찾아 일괄 등록 목록 형식으로 출력한다(읽기 전용)
#
# 데이터 파일은 .tools/project-path-gateway/ 아래 두 개다: project-path-gateway.dirs.conf(디렉터리), project-path-gateway.files.conf(파일).
# 키는 두 파일을 합쳐 유일하고, 경로 모양(마지막 이름의 확장자 유무, .으로 시작 여부)이 파일 종류와 맞아야 한다.
# 반환값: 0 성공, 1 검증 실패, 2 인자 오류·미초기화·루트 오류·데이터 파일 오류·미등록 키·종류 불일치·이미 등록된 키·목록 오류·파일 쓰기 실패.
#
# 구조: 도메인 → 애플리케이션 → 인프라 → 인터페이스 네 구획으로 나눈다.
# 도메인은 모델별 소제목(# --- 모델: ... ---)으로 나누고, 애플리케이션 구획 머리에 포트 목록(# 입력 포트:, # 출력 포트:)을 둔다.
# 이름 규칙: 인프라는 project_path_gateway__port_*(입력 포트)·project_path_gateway__infra_*(도우미)·project_path_gateway__sys_*(시스템 포트), 인터페이스는
# project_path_gateway__out_*(출력 포트 구현)·project_path_gateway__if_*(검사·결과 매핑). 출력 문구와 반환값은 인터페이스에서만 정한다(scripts/lint.sh 5절).
# project_path_gateway_init 외의 모든 함수는 서브셸 본문으로 정의해 호출 셸 상태를 바꾸지 않고,
# 본문 첫 줄에서 셸 옵션, IFS, CDPATH를 기본 상태로 되돌린다.
# 파일 시스템 접근은 인프라 구획의 시스템 포트(project_path_gateway__sys_*)에서만 한다.
# 경로를 명령 치환으로 전달하는 함수는 끝 개행이 사라지지 않도록 값 뒤에 표지 문자 x를 붙인다.
# 도메인·인터페이스의 awk 프로그램은 LC_ALL=C로 부르고 본문에 부등호, 범위 괄호식, 금지 단어를 쓰지 않는다. 필드 구분자를 LF로 두고
# 필드 1을 줄 전체로 쓴다(scripts/lint.sh 6절이 줄 단위로 리다이렉션과 셸 위치 인자 표기를 찾기 때문, 기능 008 research R-05).
# 내부 결과 코드: 3 데이터 파일 규칙 위반, 4 데이터 파일 읽기 불가, 5 경로 확인 실패,
# 6 루트 표식 파일 없음, 7 미등록 키, 8 디렉터리가 아님, 9 등록·갱신 인자 규칙 위반, 10 이미 등록된 키,
# 11 데이터 파일이 링크, 12 데이터 파일 쓰기 권한 없음, 13 데이터 파일 교체 실패,
# 14 종류 불일치(조회·갱신 대상 키가 다른 종류), 15 데이터 파일 읽기 불가이고 1.x 데이터 파일이 있음,
# 16 목록 읽기 불가, 17 목록 위반, 18 디렉터리 데이터 파일을 바꾼 뒤 파일 데이터 파일 쓰기 실패.

# === 계층: 도메인 ===

# --- 모델: 키 ---

# 키 규칙을 만족하면 반환 0. 범위 괄호식 대신 문자 목록을 명시해 로캘과 무관하게 판정한다.
# 라이브러리에서 키 규칙을 판정하는 곳은 이 함수뿐이다 (기능 005 FR-002).
project_path_gateway__domain_key_is_valid() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	'' | [!ABCDEFGHIJKLMNOPQRSTUVWXYZ]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
		return 1
		;;
	esac
	return 0
)

# --- 모델: 경로 ---

# 경로 규칙 위반 원인 코드를 출력하고 반환 1. 위반이 없으면 아무것도 출력하지 않고 반환 0. 인자는 PATH [KIND](KIND는 dir 또는 file).
# 순서: empty_path, absolute_path, parent_segment, carriage_return, line_feed, 종류 위반(not_dir_path, not_file_path).
# 종류 위반은 KIND가 있을 때만 본다. 경로 규칙과 경로 모양을 판정하는 곳은 이 함수뿐이다 (기능 005 FR-003, 기능 007 FR-016·FR-017, research R-03).
project_path_gateway__domain_path_violation() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	# 다음 줄의 작은따옴표 안에는 CR 바이트(0x0D) 하나가 들어 있다. 명령 치환 없이 비교하려고 리터럴로 둔다 (기능 005 research R-04).
	cr=''
	nl='
'
	case $1 in
	'')
		printf 'empty_path\n'
		return 1
		;;
	/*)
		printf 'absolute_path\n'
		return 1
		;;
	esac
	case /$1/ in
	*/../*)
		printf 'parent_segment\n'
		return 1
		;;
	esac
	case $1 in
	*"$cr"*)
		printf 'carriage_return\n'
		return 1
		;;
	*"$nl"*)
		printf 'line_feed\n'
		return 1
		;;
	esac
	if [ $# -lt 2 ]; then
		return 0
	fi
	# 끝 `/`를 모두 뗀 뒤 마지막 세그먼트의 모양을 본다. 끝 `/`가 있던 경로는 파일이 될 수 없다 (research R-03).
	trimmed=$1
	while :; do
		case $trimmed in
		?*/) trimmed=${trimmed%/} ;;
		*) break ;;
		esac
	done
	segment=${trimmed##*/}
	case $segment in
	.) shape='dir' ;;
	.*) shape='file' ;;
	?*.?*) shape='file' ;;
	*) shape='dir' ;;
	esac
	case $2 in
	file)
		if [ "$shape" = dir ]; then
			printf 'not_file_path\n'
			return 1
		fi
		case $1 in
		*/)
			printf 'not_file_path\n'
			return 1
			;;
		esac
		;;
	dir)
		if [ "$shape" = file ]; then
			printf 'not_dir_path\n'
			return 1
		fi
		;;
	esac
	return 0
)

# --- 모델: 항목 ---
# 항목 레코드 표현 "종류<TAB>줄번호<TAB>키<TAB>경로"는 이 소구획의 함수만 안다 (기능 005 FR-006, 기능 007 FR-003·research R-02).
# 종류는 dir 또는 file이며 항목이 적힌 데이터 파일로 정해진다.

# 항목 레코드를 만들어 출력한다(끝 LF 포함). 인자: KIND LINENO KEY PATH.
project_path_gateway__domain_entry_new() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
	return 0
)

# 레코드의 종류를 출력한다(끝 LF 없음).
project_path_gateway__domain_entry_kind() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	printf '%s' "${1%%"$tab"*}"
	return 0
)

# 레코드의 줄 번호를 출력한다(끝 LF 없음).
project_path_gateway__domain_entry_lineno() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	rest=${1#*"$tab"}
	printf '%s' "${rest%%"$tab"*}"
	return 0
)

# 레코드의 키를 출력한다(끝 LF 없음).
project_path_gateway__domain_entry_key() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	rest=${1#*"$tab"}
	rest=${rest#*"$tab"}
	printf '%s' "${rest%%"$tab"*}"
	return 0
)

# 레코드의 경로를 출력한다(끝 LF 없음). 셋째 TAB 뒤 전체이므로 경로 안 TAB을 보존한다.
project_path_gateway__domain_entry_path() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	rest=${1#*"$tab"}
	rest=${rest#*"$tab"}
	printf '%s' "${rest#*"$tab"}"
	return 0
)

# 데이터 파일 한 줄 KEY=PATH를 출력한다(끝 LF 없음).
project_path_gateway__domain_entry_to_line() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s=%s' "$1" "$2"
	return 0
)

# 등록·갱신 인자 KIND·KEY·PATH의 첫 위반 코드를 출력하고 반환 1. 위반이 없으면 아무것도 출력하지 않고 반환 0 (기능 004 research R-02).
# 순서: 키 모델, 경로 모델(경로 규칙 → 종류 규칙, 기능 007 FR-012).
project_path_gateway__domain_entry_violation() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if ! project_path_gateway__domain_key_is_valid "$2"; then
		printf 'invalid_key\n'
		return 1
	fi
	project_path_gateway__domain_path_violation "$3" "$1"
)

# 데이터 파일 한 줄을 해석한다 (기능 005 data-model 1.4, 기능 007 data-model 1.4). $1: 종류, $2: 줄 번호, $3: 줄.
# 반환 0: 유효 항목(레코드 출력), 1: 규칙 위반(원인 코드 출력), 2: 빈 줄·주석(출력 없음).
# 중복 키 검사는 두 파일 전체 상태가 필요하므로 seen_register로 따로 한다.
project_path_gateway__domain_entry_parse_line() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $3 in
	'' | '#'*) return 2 ;;
	*=*) ;;
	*)
		printf 'no_separator\n'
		return 1
		;;
	esac
	key=${3%%=*}
	path=${3#*=}
	if ! project_path_gateway__domain_key_is_valid "$key"; then
		printf 'invalid_key\n'
		return 1
	fi
	# 위반 코드는 경로 모델이 바로 이 함수의 출력으로 쓴다. 줄마다 명령 치환 한 번을 줄인다 (기능 007 research R-09).
	project_path_gateway__domain_path_violation "$path" "$1" || return 1
	# entry_new와 같은 표현. 줄마다 호출 한 번을 줄이려고 여기서 바로 만든다 (기능 005 research R-06).
	printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$key" "$path"
	return 0
)

# 줄의 첫 = 앞(키)을 출력한다. = 가 없으면 빈 출력.
project_path_gateway__domain_entry_line_key() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	*=*) printf '%s' "${1%%=*}" ;;
	esac
	return 0
)

# 줄에 CR 문자가 있으면 반환 0 (CRLF 줄 끝 안내용).
project_path_gateway__domain_entry_line_has_cr() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	# 다음 줄의 작은따옴표 안에는 CR 바이트(0x0D) 하나가 들어 있다 (기능 005 research R-04).
	cr=''
	case $1 in
	*"$cr"*) return 0 ;;
	esac
	return 1
)

# 일괄 등록 목록 한 줄을 해석한다 (기능 008 data-model 2.1, research R-09). $1: 줄 번호, $2: 줄.
# 반환 0: 항목 레코드 출력(종류는 경로 모양), 1: 위반 레코드 "!<TAB>줄번호<TAB>원인 코드<TAB>CR 있음(0·1)<TAB>줄의 키" 출력, 2: 빈 줄·주석(출력 없음).
# 판정 순서는 entry_parse_line과 같다. 종류는 경로 모델의 dir 판정이 not_dir_path이면 file이고, file로 다시 판정한 위반(끝 / 등)은 그대로 위반이다.
project_path_gateway__domain_entry_parse_list_line() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $2 in
	'' | '#'*) return 2 ;;
	*=*)
		key=${2%%=*}
		path=${2#*=}
		if project_path_gateway__domain_key_is_valid "$key"; then
			kind=dir
			code=$(project_path_gateway__domain_path_violation "$path" dir)
			if [ "$code" = not_dir_path ]; then
				kind='file'
				code=$(project_path_gateway__domain_path_violation "$path" file)
			fi
			if [ -z "$code" ]; then
				printf '%s\t%s\t%s\t%s\n' "$kind" "$1" "$key" "$path"
				return 0
			fi
		else
			code=invalid_key
		fi
		;;
	*)
		key=
		code=no_separator
		;;
	esac
	cr=0
	if project_path_gateway__domain_entry_line_has_cr "$2"; then
		cr=1
	fi
	printf '!\t%s\t%s\t%s\t%s\n' "$1" "$code" "$cr" "$key"
	return 1
)

# --- 모델: 항목 목록 ---

# 본 키 목록 SEEN(":KEY=종류/줄번호:" 연결)에 레코드의 키를 등록한다 (기능 007 research R-06).
# 처음 본 키이면 새 목록을 출력하고 반환 0, 이미 본 키이면 처음 정의된 위치 "종류/줄번호"를 출력하고 반환 1.
project_path_gateway__domain_seen_register() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	kind=${2%%"$tab"*}
	rest=${2#*"$tab"}
	lineno=$kind/${rest%%"$tab"*}
	rest=${rest#*"$tab"}
	key=${rest%%"$tab"*}
	case $1 in
	*":$key="*)
		rest=${1#*":$key="}
		printf '%s\n' "${rest%%:*}"
		return 1
		;;
	esac
	if [ -z "$1" ]; then
		printf ':%s=%s:' "$key" "$lineno"
	else
		printf '%s%s=%s:' "$1" "$key" "$lineno"
	fi
	return 0
)

# 항목 목록 RECORDS(레코드를 LF로 이은 문자열)에서 키가 정확히 KEY인 첫 레코드를 출력한다(끝 LF 없음). 없으면 반환 1.
project_path_gateway__domain_entries_find() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	nl='
'
	rest=$1
	while [ -n "$rest" ]; do
		case $rest in
		*"$nl"*)
			record=${rest%%"$nl"*}
			rest=${rest#*"$nl"}
			;;
		*)
			record=$rest
			rest=
			;;
		esac
		key=${record#*"$tab"}
		key=${key#*"$tab"}
		if [ "${key%%"$tab"*}" = "$2" ]; then
			printf '%s' "$record"
			return 0
		fi
	done
	return 1
)

# 항목 목록 RECORDS의 레코드마다 종류, 키, 경로를 한 줄씩(LF로 끝나게) 차례로 출력한다 (기능 007 research R-09).
# 경로에는 LF가 없으므로(경로 모델) 받는 쪽은 레코드마다 세 줄을 읽으면 된다. 레코드마다 필드 접근 함수를 부르지 않으려고 쓴다.
project_path_gateway__domain_entries_fields() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	nl='
'
	rest=$1
	while [ -n "$rest" ]; do
		case $rest in
		*"$nl"*)
			record=${rest%%"$nl"*}
			rest=${rest#*"$nl"}
			;;
		*)
			record=$rest
			rest=
			;;
		esac
		[ -n "$record" ] || continue
		field=${record#*"$tab"}
		field=${field#*"$tab"}
		printf '%s\n%s\n%s\n' "${record%%"$tab"*}" "${field%%"$tab"*}" "${field#*"$tab"}"
	done
	return 0
)

# 일괄 등록 목록 결과 ITEMS(entry_parse_list_line 출력을 이은 것)의 줄마다 루트와 결합한 절대경로를 한 줄씩 출력한다.
# 위반 레코드(!)는 빈 줄이다. 결합 규칙은 domain_join과 같다 (기능 008 research R-09 4단계). $1: 루트, $2: ITEMS.
project_path_gateway__domain_entries_full_paths() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	{
		printf '%s\n' "$1"
		printf '%s\n' "$2"
	} | LC_ALL=C awk '
	BEGIN { FS = "\n" }
	NR == 1 {
		root = $1
		if (substr(root, length(root)) == "/") root = substr(root, 1, length(root) - 1)
		next
	}
	$1 == "" { next }
	substr($1, 1, 2) == "!\t" { print ""; next }
	{
		rest = $1
		for (i = 0; i != 3; i++) rest = substr(rest, index(rest, "\t") + 1)
		print root "/" rest
	}'
)

# 일괄 등록 목록을 목록 줄 순서대로 판정한다 (기능 008 data-model 2.2, research R-09 5단계). $1: 기존 항목 목록 RECORDS, $2: 목록 결과 ITEMS,
# $3: ITEMS 항목 줄마다의 실제 종류(dir, file, other, none. 모자라면 none). 출력: 등록 "A<TAB>종류<TAB>줄번호<TAB>키<TAB>경로", 유지 "K<TAB>줄번호<TAB>키",
# 위반은 "V" 한 줄 뒤 줄 번호, 코드, 키, 상세1, 상세2 다섯 줄. 한 줄에 위반 하나: 줄 위반 → 실제 종류 → 목록 안 중복 키 → 기존 항목.
# 키·경로 규칙은 entry_parse_list_line이 이미 판정했고 여기서는 집합 비교만 한다.
project_path_gateway__domain_entries_check_list() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	{
		printf '%s\n' "$1"
		printf '\001\n'
		printf '%s\n' "$3"
		printf '\001\n'
		printf '%s\n' "$2"
	} | LC_ALL=C awk '
	BEGIN { FS = "\n" }
	# TAB 구분 레코드의 N번째 필드와 N번째 TAB 뒤 전체
	function tab_field(s, n,   i, j) {
		for (i = 1; i != n; i++) s = substr(s, index(s, "\t") + 1)
		j = index(s, "\t")
		return j ? substr(s, 1, j - 1) : s
	}
	function tab_rest(s, n,   i) {
		for (i = 0; i != n; i++) s = substr(s, index(s, "\t") + 1)
		return s
	}
	function violation(lineno, code, key, first, second) {
		printf "V\n%s\n%s\n%s\n%s\n%s\n", lineno, code, key, first, second
	}
	BEGIN { part = 1; n = 0; m = 0 }
	$1 == "\001" { part++; next }
	part == 1 {
		if ($1 == "") next
		key = tab_field($1, 3)
		have[key] = 1
		have_kind[key] = tab_field($1, 1)
		have_path[key] = tab_rest($1, 3)
		next
	}
	part == 2 { actual[++n] = $1; next }
	$1 == "" { next }
	{
		m++
		if (substr($1, 1, 2) == "!\t") {
			violation(tab_field($1, 2), tab_field($1, 3), tab_rest($1, 4), tab_field($1, 4), "")
			next
		}
		kind = tab_field($1, 1)
		lineno = tab_field($1, 2)
		key = tab_field($1, 3)
		path = tab_rest($1, 3)
		real = (m in actual) ? actual[m] : ""
		if (real == "") real = "none"
		first = (key in first_line) ? first_line[key] : ""
		if (first == "") first_line[key] = lineno
		if (real != "none" && real != kind) { violation(lineno, "kind_mismatch", key, kind, real); next }
		if (first != "") { violation(lineno, "duplicate_key", key, first, ""); next }
		if (key in have) {
			if (have_kind[key] == kind && have_path[key] == path) { printf "K\t%s\t%s\n", lineno, key; next }
			violation(lineno, "key_conflict", key, have_kind[key], have_path[key])
			next
		}
		printf "A\t%s\t%s\t%s\t%s\n", kind, lineno, key, path
	}'
)

# 판정 스트림 CHECKED의 위반마다 줄 번호, 코드, 키, 상세1, 상세2를 한 줄씩(다섯 줄) 출력한다. 위반이 없으면 빈 출력 (기능 008 data-model 2.2).
project_path_gateway__domain_entries_list_violations() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s\n' "$1" | LC_ALL=C awk '
	BEGIN { FS = "\n" }
	left { print; left--; next }
	$1 == "V" { left = 5 }'
)

# 판정 스트림 CHECKED에서 종류 KIND(dir, file)의 등록 항목을 목록 순서대로 KEY=경로 줄(entry_to_line과 같은 형식)로 만들어 LF로 이어 출력한다.
# 끝 LF는 붙이지 않고, 등록할 항목이 없으면 빈 출력이다 (기능 008 research R-09 7단계).
project_path_gateway__domain_entries_list_block() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	{
		printf '%s\n' "$2"
		printf '%s\n' "$1"
	} | LC_ALL=C awk '
	BEGIN { FS = "\n" }
	# TAB 구분 레코드의 N번째 필드와 N번째 TAB 뒤 전체
	function tab_field(s, n,   i, j) {
		for (i = 1; i != n; i++) s = substr(s, index(s, "\t") + 1)
		j = index(s, "\t")
		return j ? substr(s, 1, j - 1) : s
	}
	function tab_rest(s, n,   i) {
		for (i = 0; i != n; i++) s = substr(s, index(s, "\t") + 1)
		return s
	}
	NR == 1 { want = $1; next }
	left { left--; next }
	$1 == "V" { left = 5; next }
	substr($1, 1, 2) == "A\t" && tab_field($1, 2) == want {
		line = tab_field($1, 4) "=" tab_rest($1, 4)
		block = (count == 0) ? line : block "\n" line
		count++
	}
	END { if (count) printf "%s", block }'
)

# 판정 스트림 CHECKED의 디렉터리 등록 수, 파일 등록 수, 유지 수를 공백으로 이어 한 줄로 출력한다 (기능 008 research R-09 9단계).
project_path_gateway__domain_entries_list_counts() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s\n' "$1" | LC_ALL=C awk '
	BEGIN { FS = "\n" }
	BEGIN { dirs = 0; files = 0; kept = 0 }
	left { left--; next }
	$1 == "V" { left = 5; next }
	substr($1, 1, 2) == "K\t" { kept++; next }
	substr($1, 1, 6) == "A\tdir\t" { dirs++; next }
	substr($1, 1, 7) == "A\tfile\t" { files++; next }
	END { printf "%d %d %d\n", dirs, files, kept }'
)

# --- 모델: 도구 배치 ---

# 루트 표식 파일의 루트 기준 상대경로를 출력한다(끝 LF 없음).
project_path_gateway__domain_layout_marker() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s' .tools/project-path-gateway/.project-path-gateway
	return 0
)

# 종류 KIND(dir, file)의 데이터 파일 루트 기준 상대경로를 출력한다(끝 LF 없음) (기능 007 research R-01).
project_path_gateway__domain_layout_data_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	file) printf '%s' .tools/project-path-gateway/project-path-gateway.files.conf ;;
	*) printf '%s' .tools/project-path-gateway/project-path-gateway.dirs.conf ;;
	esac
	return 0
)

# 데이터 파일 종류를 읽는 순서대로 출력한다(끝 LF 없음) (기능 007 FR-002).
project_path_gateway__domain_layout_kinds() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s' 'dir file'
	return 0
)

# 1.x 데이터 파일의 루트 기준 상대경로를 출력한다(끝 LF 없음). 라이브러리는 이 파일을 읽지 않는다 (기능 007 FR-031).
project_path_gateway__domain_layout_legacy_data_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s' .tools/project-path-gateway/project-path-gateway.conf
	return 0
)

# 루트 기준 상대경로 REL이 도구 디렉터리나 에이전트 스킬 디렉터리 아래이면 반환 0. 찾기는 이 파일들을 읽거나 후보로 내지 않는다 (기능 008 research R-02).
project_path_gateway__domain_layout_is_tool_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	.tools/project-path-gateway/* | .agents/skills/project-path-gateway/*) return 0 ;;
	esac
	return 1
)

# --- 모델: 찾기 ---
# 기존 프로젝트 셸 스크립트의 경로 표기 추출·해석·분류 (기능 008 research R-02~R-07). 레코드 형식은 기능 008 data-model 3절이다.

# 찾기 후보 파일 FILE(루트 ROOT 아래 절대경로)의 처리를 한 줄로 출력한다: skip(도구 파일, 이름에 TAB·CR), script(.sh), check(첫 줄 shebang 확인 필요).
project_path_gateway__domain_scan_file_class() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	case $2 in
	*"$tab"*)
		printf 'skip\n'
		return 0
		;;
	esac
	if project_path_gateway__domain_entry_line_has_cr "$2"; then
		printf 'skip\n'
		return 0
	fi
	case $1 in
	/) rel=${2#/} ;;
	*) rel=${2#"$1"/} ;;
	esac
	if project_path_gateway__domain_layout_is_tool_file "$rel"; then
		printf 'skip\n'
		return 0
	fi
	case $rel in
	*.sh) printf 'script\n' ;;
	*) printf 'check\n' ;;
	esac
	return 0
)

# 첫 줄 LINE이 sh, bash, dash, zsh, ksh shebang이면 반환 0. env 경유(옵션·VAR=값 건너뜀)와 끝 CR을 허용한다 (기능 008 contracts/library-api.md 1절).
project_path_gateway__domain_scan_is_shell_shebang() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	'#!'*) ;;
	*) return 1 ;;
	esac
	cr=$(printf '\r')
	line=${1#??}
	line=${line%"$cr"}
	set -f
	# shellcheck disable=SC2086 # 인터프리터와 인자를 공백으로 나눈다
	set -- $line
	[ "$#" -gt 0 ] || return 1
	name=${1##*/}
	if [ "$name" = env ]; then
		shift
		while [ "$#" -gt 0 ]; do
			case $1 in
			-* | *=*) shift ;;
			*) break ;;
			esac
		done
		[ "$#" -gt 0 ] || return 1
		name=${1##*/}
	fi
	case $name in
	sh | bash | dash | zsh | ksh) return 0 ;;
	esac
	return 1
)

# 스크립트 FILE의 본문 BODY를 찾기 스트림으로 출력한다: "F<TAB>FILE" 한 줄과 본문 줄마다 "L<TAB>원문" (기능 008 data-model 3.1).
project_path_gateway__domain_scan_script_lines() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf 'F\t%s\n' "$1"
	[ -n "$2" ] || return 0
	printf '%s\n' "$2" | LC_ALL=C awk '
	BEGIN { FS = "\n" }
	{ printf "L\t%s\n", $1 }'
)

# 스크립트 스트림 LINES에서 경로 표기를 뽑아 해석 대상(T)과 발견 위치(O)를 낸다 (기능 008 research R-04, data-model 3.2).
# $1: 루트, $2: 항목 목록 RECORDS(기존 키 K와 등록 경로 G를 함께 낸다), $3: script_lines 출력을 이은 스트림.
# 표기 추출: 따옴표·이스케이프·치환을 처리해 단어로 나누고, 치환 뒤 / 다음 부분, NAME=값의 값을 본다. 공백이 든 값은 전체(맨 이름)와 조각을 보고,
# 조각의 발견 위치에 값 전체의 대상 번호를 붙인다(값 전체가 있으면 분류가 조각을 뺀다).
# 해석: ./·../·.. 표기는 스크립트 디렉터리 기준, 루트/로 시작하는 절대 표기는 루트 기준(절대 표시), 그 밖은 루트 기준(1순위)과 스크립트 디렉터리 기준(2순위).
project_path_gateway__domain_scan_extract() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	{
		printf '%s\n' "$1"
		printf '\001\n'
		project_path_gateway__domain_entries_fields "$2"
		printf '\001\n'
		printf '%s\n' "$3"
	} | LC_ALL=C awk '
	BEGIN {
		FS = "\n"
		part = 1
		MARK = sprintf("%c", 1)
		SQ = sprintf("%c", 39)
		DQ = "\""
		NAMEC = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_"
		DIGIT = "0123456789"
		ASSIGN = "^[" NAMEC "][" NAMEC DIGIT "]*="
		ntarget = 0
		nscripts = 0
		active = 0
	}
	# 루트 기준 상대경로 결합과 어휘적 정규화. 루트 위로 나가면 nerr = 1.
	function norm(base, rel,   n, seg, k, top, out, i) {
		nerr = 0
		top = 0
		n = split(base, seg, "/")
		for (k = 1; (k in seg); k++) if (seg[k] != "" && seg[k] != ".") stack[++top] = seg[k]
		n = split(rel, seg, "/")
		for (k = 1; (k in seg); k++) {
			if (seg[k] == "" || seg[k] == ".") continue
			if (seg[k] == "..") {
				if (top == 0) { nerr = 1; return "" }
				top--
				continue
			}
			stack[++top] = seg[k]
		}
		out = ""
		for (i = 1; i != top + 1; i++) out = (i == 1) ? stack[i] : out "/" stack[i]
		return out
	}
	function has_parent(e) { return ("/" e "/") ~ /\/\.\.\// }
	# 대상 번호를 정하고(처음이면 T를 낸다) 발견 위치 O를 낸다. whole은 이 표기를 조각으로 품은 값 전체의 대상 번호(없으면 -). 대상 번호를 돌려준다.
	function target(cls, first, second, raw, absflag, whole,   key) {
		key = cls "\t" first "\t" second
		if (!(key in tid)) {
			tid[key] = ++ntarget
			printf "T\t%d\t%s\t%s\t%s\n", ntarget, cls, first, second
		}
		printf "O\t%d\t%s\t%d\t%s\t%s\t%s\n", tid[key], script, lineno, absflag, whole, raw
		return tid[key]
	}
	# 표기 하나를 해석해 대상과 발견 위치를 내고 대상 번호를 돌려준다(버리면 0). bare가 참이면 경로 같음으로 보지 않는다.
	function add_expr(e, raw, bare, whole,   rel, n1, n2, cls, c1) {
		c1 = substr(e, 1, 1)
		if (e == "" || e == "." || c1 == "~" || c1 == "-") return 0
		if (index(e, "*") || index(e, "?") || index(e, "[") || index(e, "://")) return 0
		if (index(e, "\t") || index(e, "\r") || index(e, "$") || index(e, "\\") || index(e, MARK)) return 0
		if (c1 == "/") {
			if (e == root) return target("r", "", "", raw, "a", whole)
			if (index(e, rootsl) != 1) return 0
			rel = substr(e, length(rootsl) + 1)
			n1 = norm("", rel)
			if (nerr) return 0
			if (n1 == "") return target("r", "", "", raw, "a", whole)
			return target("p", n1, "", raw, "a", whole)
		}
		if (e == ".." || substr(e, 1, 2) == "./" || substr(e, 1, 3) == "../") {
			n1 = norm(sdir, e)
			if (nerr) return 0
			if (n1 == "") return has_parent(e) ? target("r", "", "", raw, "-", whole) : 0
			return target("p", n1, "", raw, "-", whole)
		}
		cls = (bare || !index(e, "/")) ? "b" : "p"
		n1 = norm("", e)
		if (nerr) n1 = ""
		n2 = ""
		if (sdir != "") {
			n2 = norm(sdir, e)
			if (nerr || n2 == n1) n2 = ""
		}
		if (n1 == "") { n1 = n2; n2 = "" }
		if (n1 == "") return 0
		return target(cls, n1, n2, raw, "-", whole)
	}
	# 값 하나: 치환이 있으면 마지막 치환 뒤 / 다음 부분만 본다. 대상 번호를 돌려준다(버리면 0).
	function piece_expr(v, raw, bare, whole,   j) {
		if (index(v, MARK)) {
			while ((j = index(v, MARK))) v = substr(v, j + 1)
			if (substr(v, 1, 1) != "/") return 0
			v = substr(v, 2)
		}
		return add_expr(v, raw, bare, whole)
	}
	# 공백·TAB이 든 값(따옴표·이스케이프)은 값 전체를 맨 이름 한 표기로 보고, 공백으로 나눈 조각도 표기로 본다.
	# 조각의 발견 위치에는 값 전체의 대상 번호를 붙여, 값 전체가 실제로 있으면 분류 단계에서 조각을 빼게 한다.
	function word_end(raw, lit,   v, eq, k, piece, whole) {
		v = lit
		if (substr(v, 1, 1) == "-") {
			eq = index(v, "=")
			if (eq == 0) return
			v = substr(v, eq + 1)
		} else if (v ~ ASSIGN) {
			v = substr(v, index(v, "=") + 1)
		}
		if (v == "") return
		if (index(v, " ") || index(v, "\t")) {
			whole = piece_expr(v, raw, 1, "-")
			split(v, piece, /[ \t]+/)
			for (k = 1; (k in piece); k++) piece_expr(piece[k], raw, 0, whole ? whole : "-")
			return
		}
		piece_expr(v, raw, 0, "-")
	}
	# 큰따옴표 안을 건너뛰고 닫는 따옴표 다음 위치를 돌려준다(치환 안의 따옴표 포함).
	function dq_skip(s, i,   c) {
		while ((c = substr(s, i, 1)) != "") {
			if (c == "\\") { i += 2; continue }
			if (c == DQ) return i + 1
			if (c == "$" && substr(s, i + 1, 1) == "(") { i = paren_end(s, i + 1); continue }
			i++
		}
		return i
	}
	# 위치 i의 여는 괄호와 짝인 닫는 괄호 다음 위치. 따옴표 안 괄호는 세지 않는다.
	function paren_end(s, i,   depth, c, j) {
		depth = 0
		while ((c = substr(s, i, 1)) != "") {
			if (c == "\\") { i += 2; continue }
			if (c == SQ) {
				j = index(substr(s, i + 1), SQ)
				if (j == 0) return length(s) + 1
				i += j + 1
				continue
			}
			if (c == DQ) { i = dq_skip(s, i + 1); continue }
			if (c == "(") depth++
			if (c == ")") {
				depth--
				if (depth == 0) return i + 1
			}
			i++
		}
		return i
	}
	function brace_end(s, i,   depth, c) {
		depth = 0
		while ((c = substr(s, i, 1)) != "") {
			if (c == "\\") { i += 2; continue }
			if (c == DQ) { i = dq_skip(s, i + 1); continue }
			if (c == "{") depth++
			if (c == "}") {
				depth--
				if (depth == 0) return i + 1
			}
			i++
		}
		return i
	}
	# 위치 i의 치환($ 또는 백틱)이 끝난 다음 위치. 치환이 아니면 i. 명령 치환 안의 글은 다시 처리한다.
	function subst_end(s, i,   c, j, q) {
		if (substr(s, i, 1) == "`") {
			j = i + 1
			while ((q = substr(s, j, 1)) != "" && q != "`") j += (q == "\\") ? 2 : 1
			scan_line(substr(s, i + 1, j - i - 1))
			return (q == "") ? j : j + 1
		}
		c = substr(s, i + 1, 1)
		if (c == "") return i
		if (c == "(") {
			j = paren_end(s, i + 1)
			if (substr(s, i + 2, 1) != "(") scan_line(substr(s, i + 2, j - i - 3))
			return j
		}
		if (c == "{") return brace_end(s, i + 1)
		if (index(NAMEC, c)) {
			j = i + 1
			while ((q = substr(s, j, 1)) != "" && (index(NAMEC, q) || index(DIGIT, q))) j++
			return j
		}
		if (index(DIGIT, c) || index("@*#?!-", c) || c == "$") return i + 2
		return i
	}
	function dquote(s, i,   c, out, j, n) {
		out = ""
		while ((c = substr(s, i, 1)) != "") {
			if (c == DQ) { qlit = out; return i + 1 }
			if (c == "\\") {
				n = substr(s, i + 1, 1)
				if (n == DQ || n == "\\" || n == "$" || n == "`") { out = out n; i += 2; continue }
				out = out c
				i++
				continue
			}
			if (c == "$" || c == "`") {
				j = subst_end(s, i)
				if (j == i) { out = out c; i++; continue }
				out = out MARK
				i = j
				continue
			}
			out = out c
			i++
		}
		qlit = out
		return i
	}
	# 한 줄(또는 명령 치환 안의 글)을 단어로 나눠 처리한다.
	function scan_line(s,   i, c, lit, start, inword, j) {
		i = 1
		inword = 0
		lit = ""
		while ((c = substr(s, i, 1)) != "") {
			if (c == " " || c == "\t" || index(";&|()<>", c)) {
				if (inword) word_end(substr(s, start, i - start), lit)
				inword = 0
				lit = ""
				i++
				continue
			}
			if (!inword) {
				if (c == "#") return
				inword = 1
				start = i
				lit = ""
			}
			if (c == "\\") { lit = lit substr(s, i + 1, 1); i += 2; continue }
			if (c == SQ) {
				j = index(substr(s, i + 1), SQ)
				if (j == 0) { lit = lit substr(s, i + 1); i = length(s) + 1; continue }
				lit = lit substr(s, i + 1, j - 1)
				i += j + 1
				continue
			}
			if (c == DQ) { i = dquote(s, i + 1); lit = lit qlit; continue }
			if (c == "$" || c == "`") {
				j = subst_end(s, i)
				if (j == i) { lit = lit c; i++; continue }
				lit = lit MARK
				i = j
				continue
			}
			lit = lit c
			i++
		}
		if (inword) word_end(substr(s, start, i - start), lit)
	}
	$1 == "\001" { part++; nfield = 0; next }
	part == 1 {
		root = $1
		rootsl = (root == "/") ? "/" : root "/"
		printf "ROOT\t%s\n", root
		next
	}
	part == 2 {
		nfield++
		if (nfield == 1) { ekind = $1; next }
		if (nfield == 2) { ekey = $1; next }
		nfield = 0
		printf "K\t%s\n", ekey
		p = norm("", $1)
		if (!nerr && p != "") printf "G\t%s:%s\t%s\n", ekind, ekey, p
		next
	}
	substr($1, 1, 2) == "F\t" {
		nscripts++
		lineno = 0
		active = (index(substr($1, 3), rootsl) == 1)
		script = substr($1, 3 + length(rootsl))
		sdir = ""
		rest = script
		while ((j = index(rest, "/"))) {
			sdir = (sdir == "") ? substr(rest, 1, j - 1) : sdir "/" substr(rest, 1, j - 1)
			rest = substr(rest, j + 1)
		}
		next
	}
	substr($1, 1, 2) == "L\t" {
		lineno++
		if (!active) next
		text = substr($1, 3)
		if (substr(text, length(text)) == "\r") text = substr(text, 1, length(text) - 1)
		head = text
		sub(/^[ \t]+/, "", head)
		if (substr(head, 1, 1) == "#") next
		scan_line(text)
		next
	}
	END { printf "P\t%d\n", nscripts }
	'
)

# 추출 스트림 EXTRACTED의 해석 대상마다 1순위·2순위 절대경로를 한 줄씩(없으면 빈 줄) 출력한다. 루트 참조는 빈 줄 두 개다 (기능 008 research R-06 1단계).
project_path_gateway__domain_scan_probe_paths() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s\n' "$1" | LC_ALL=C awk '
	BEGIN { FS = "\n" }
	function tab_field(s, n,   i, j) {
		for (i = 1; i != n; i++) s = substr(s, index(s, "\t") + 1)
		j = index(s, "\t")
		return j ? substr(s, 1, j - 1) : s
	}
	function tab_rest(s, n,   i) {
		for (i = 0; i != n; i++) s = substr(s, index(s, "\t") + 1)
		return s
	}
	substr($1, 1, 5) == "ROOT\t" {
		root = substr($1, 6)
		if (substr(root, length(root)) == "/") root = substr(root, 1, length(root) - 1)
		next
	}
	substr($1, 1, 2) == "T\t" {
		if (tab_field($1, 3) == "r") { print ""; print ""; next }
		print root "/" tab_field($1, 4)
		second = tab_rest($1, 4)
		print (second == "") ? "" : root "/" second
	}'
)

# 해석 대상마다 실제로 있는 1순위, 없으면 2순위를 고른다 (기능 008 research R-06 3단계, data-model 3.3). $1: EXTRACTED, $2: probe_paths 순서의 종류 줄들.
# 확인할 대상마다 번호, 상태(dir, file, other, none, root), 루트 기준 경로, 절대경로 네 줄을 낸다. 맨 이름이 어디에도 없으면 내지 않는다.
project_path_gateway__domain_scan_pick() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	{
		printf '%s\n' "$2"
		printf '\001\n'
		printf '%s\n' "$1"
	} | LC_ALL=C awk '
	BEGIN { FS = "\n"; part = 1; n = 0; t = 0 }
	function tab_field(s, n,   i, j) {
		for (i = 1; i != n; i++) s = substr(s, index(s, "\t") + 1)
		j = index(s, "\t")
		return j ? substr(s, 1, j - 1) : s
	}
	function tab_rest(s, n,   i) {
		for (i = 0; i != n; i++) s = substr(s, index(s, "\t") + 1)
		return s
	}
	function found(k) { return k == "dir" || k == "file" || k == "other" }
	part == 1 {
		if ($1 == "\001") { part = 2; next }
		kinds[++n] = $1
		next
	}
	substr($1, 1, 5) == "ROOT\t" {
		root = substr($1, 6)
		if (substr(root, length(root)) == "/") root = substr(root, 1, length(root) - 1)
		next
	}
	substr($1, 1, 2) == "T\t" {
		t++
		id = tab_field($1, 2)
		cls = tab_field($1, 3)
		first = tab_field($1, 4)
		second = tab_rest($1, 4)
		k1 = ((2 * t - 1) in kinds) ? kinds[2 * t - 1] : ""
		k2 = ((2 * t) in kinds) ? kinds[2 * t] : ""
		if (cls == "r") { printf "%s\nroot\n\n\n", id; next }
		if (found(k1)) { printf "%s\n%s\n%s\n%s\n", id, k1, first, root "/" first; next }
		if (second != "" && found(k2)) { printf "%s\n%s\n%s\n%s\n", id, k2, second, root "/" second; next }
		if (cls == "p") printf "%s\nnone\n%s\n\n", id, first
	}'
)

# 없는 경로 PATH의 종류를 경로 모양으로 추정해 dir 또는 file을 한 줄로 출력한다(경로 모델 판정을 쓴다, 기능 008 research R-06 4단계).
project_path_gateway__domain_scan_guess_kind() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$(project_path_gateway__domain_path_violation "$1" dir)" = not_dir_path ]; then
		printf 'file\n'
	else
		printf 'dir\n'
	fi
	return 0
)

# 해석 결과 레코드 "S<TAB>번호<TAB>상태<TAB>종류<TAB>원인<TAB>경로"를 출력한다. 빈 종류·원인은 - 로 쓴다 (기능 008 data-model 3.4).
project_path_gateway__domain_scan_resolution() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf 'S\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "${3:--}" "${4:--}" "$5"
	return 0
)

# 추출 스트림 EXTRACTED와 해석 결과 RESOLVED로 후보 스트림을 만든다 (기능 008 research R-07, data-model 3.4).
# 분류(새 후보, 이미 등록, 등록 불가, 확인 필요, 루트 참조) → 같은 분류·경로 병합 → 정렬(분류, 경로 바이트, 스크립트, 줄 번호) → 같은 위치 한 번 → 제안 키.
# 값 전체가 실제로 있으면(해석 결과가 있으면) 그 값의 조각으로 찾은 발견 위치는 뺀다. 남은 위치가 없는 대상은 후보가 아니다.
project_path_gateway__domain_scan_group() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	{
		printf '%s\n' "$1"
		printf '%s\n' "$2"
	} | LC_ALL=C awk '
	BEGIN { FS = "\n"; scripts = 0; ns = 0 }
	function tab_field(s, n,   i, j) {
		for (i = 1; i != n; i++) s = substr(s, index(s, "\t") + 1)
		j = index(s, "\t")
		return j ? substr(s, 1, j - 1) : s
	}
	function tab_rest(s, n,   i) {
		for (i = 0; i != n; i++) s = substr(s, index(s, "\t") + 1)
		return s
	}
	substr($1, 1, 2) == "P\t" { scripts = substr($1, 3); next }
	substr($1, 1, 2) == "K\t" { printf "0\t\t0\tK\t%s\n", substr($1, 3); next }
	substr($1, 1, 2) == "G\t" {
		p = tab_rest($1, 2)
		reg[p] = (p in reg) ? reg[p] " " tab_field($1, 2) : tab_field($1, 2)
		next
	}
	substr($1, 1, 2) == "O\t" {
		id = tab_field($1, 2)
		nloc[id]++
		loc[id, nloc[id]] = tab_field($1, 3) "\t" tab_field($1, 4) "\t" tab_field($1, 5) "\t" tab_rest($1, 6)
		whole[id, nloc[id]] = tab_field($1, 6)
		next
	}
	substr($1, 1, 2) == "S\t" {
		ns++
		found[tab_field($1, 2)] = 1
		sid[ns] = tab_field($1, 2)
		sst[ns] = tab_field($1, 3)
		skind[ns] = tab_field($1, 4)
		scause[ns] = tab_field($1, 5)
		spath[ns] = tab_rest($1, 5)
		next
	}
	END {
		for (i = 1; (i in sid); i++) {
			id = sid[i]
			p = spath[i]
			kind = skind[i]
			info = "-"
			if (sst[i] == "root") { rank = 5; kind = "-"; p = "" }
			else if (p in reg) { rank = 2; info = reg[p]; kind = substr(info, 1, index(info, ":") - 1) }
			else if (sst[i] == "ok") rank = 1
			else if (sst[i] == "blocked") { rank = 3; info = scause[i] }
			else if (sst[i] == "missing") rank = 4
			else continue
			kept = 0
			for (j = 1; j != nloc[id] + 1; j++) {
				if (whole[id, j] != "-" && (whole[id, j] in found)) continue
				kept++
				out[kept] = loc[id, j]
			}
			if (kept == 0) continue
			if (!((rank, p) in head)) {
				head[rank, p] = 1
				printf "%d\t%s\t0\t%s\t%s\n", rank, p, kind, info
			}
			for (j = 1; j != kept + 1; j++) printf "%d\t%s\t1\t%s\n", rank, p, out[j]
		}
		printf "~\t%d\n", scripts
	}
	' | LC_ALL=C sort -t "$tab" -k1,1 -k2,2 -k3,3 -k4,4 -k5,5n | LC_ALL=C awk '
	BEGIN {
		FS = "\n"
		DIGIT = "0123456789"
		name[1] = "new"
		name[2] = "registered"
		name[3] = "blocked"
		name[4] = "missing"
		name[5] = "root"
		n = 0
		scripts = 0
	}
	function tab_field(s, n,   i, j) {
		for (i = 1; i != n; i++) s = substr(s, index(s, "\t") + 1)
		j = index(s, "\t")
		return j ? substr(s, 1, j - 1) : s
	}
	function tab_rest(s, n,   i) {
		for (i = 0; i != n; i++) s = substr(s, index(s, "\t") + 1)
		return s
	}
	# 제안 키: 대문자화, 대문자·숫자 밖은 _, 연속 _는 하나, 앞뒤 _ 제거, 비면 PATH, 숫자 시작이면 PATH_ 접두, 겹치면 _2부터.
	function suggest(p,   k, base, m) {
		k = toupper(p)
		gsub(/[^ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]/, "_", k)
		gsub(/__+/, "_", k)
		sub(/^_/, "", k)
		sub(/_$/, "", k)
		if (k == "") k = "PATH"
		else if (index(DIGIT, substr(k, 1, 1))) k = "PATH_" k
		base = k
		m = 1
		while (k in used) {
			m++
			k = base "_" m
		}
		used[k] = 1
		return k
	}
	$1 == prev { next }
	{ prev = $1 }
	substr($1, 1, 2) == "0\t" { used[tab_rest($1, 4)] = 1; next }
	substr($1, 1, 2) == "~\t" { scripts = substr($1, 3); next }
	tab_field($1, 3) == "0" {
		rank = tab_field($1, 1)
		p = tab_field($1, 2)
		info = tab_rest($1, 4)
		if (rank == 1 || rank == 4) info = suggest(p)
		count[rank]++
		out[++n] = "C\t" name[rank] "\t" tab_field($1, 4) "\t" info "\t" p
		next
	}
	{ out[++n] = "@\t" tab_rest($1, 3) }
	END {
		printf "N\t%d\t%d\t%d\t%d\t%d\t%d\n", scripts, count[1], count[2], count[3], count[4], count[5]
		for (i = 1; i != n + 1; i++) print out[i]
	}
	'
)

# --- 기타 규칙 ---
# 데이터 파일 원문 편집, 루트 결합, 루트 내부 판정.

# 등록 새 원문을 끝 표지 방식으로 출력한다 (기능 004 research R-05). 원문 끝에 줄(domain_entry_to_line 결과)과 LF를 더하며,
# 원문이 LF 없이 끝나면 LF를 먼저 더한다.
project_path_gateway__domain_append_entry() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	nl='
'
	case $1 in
	'' | *"$nl") printf '%s%s\nx' "$1" "$2" ;;
	*) printf '%s\n%s\nx' "$1" "$2" ;;
	esac
	return 0
)

# 갱신 새 원문을 끝 표지 방식으로 출력한다 (기능 004 research R-05). 원문을 LF 기준으로 나눠 LINENO번째 줄 내용만
# LINE으로 바꾸고, LF 위치와 파일 끝 LF 유무는 그대로 둔다. 줄 수보다 큰 LINENO이면 반환 1.
project_path_gateway__domain_replace_line() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	nl='
'
	rest=$1
	done_part=
	n=0
	while [ -n "$rest" ]; do
		n=$((n + 1))
		case $rest in
		*"$nl"*)
			current=${rest%%"$nl"*}
			rest=${rest#*"$nl"}
			sep=$nl
			;;
		*)
			current=$rest
			rest=
			sep=
			;;
		esac
		if [ "$n" -eq "$2" ]; then
			printf '%s%s%s%sx' "$done_part" "$3" "$sep" "$rest"
			return 0
		fi
		done_part=$done_part$current$sep
	done
	return 1
)

# 루트와 상대경로를 결합해 출력한다. 루트가 /이면 슬래시를 중복하지 않는다.
project_path_gateway__domain_join() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s/%s\n' "${1%/}" "$2"
	return 0
)

# 물리 경로 PHYS가 루트와 같거나 루트 아래이면 반환 0 (접두어 경계 적용).
project_path_gateway__domain_is_inside() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ "$1" = / ] && return 0
	[ "$2" = "$1" ] && return 0
	case $2 in
	"$1"/*) return 0 ;;
	esac
	return 1
)

# === 계층: 애플리케이션 ===

# 입력 포트: project_path_gateway__port_is_dir project_path_gateway__port_physical_dir project_path_gateway__port_readable_file
# 입력 포트: project_path_gateway__port_read_lines project_path_gateway__port_find_root project_path_gateway__port_exists
# 입력 포트: project_path_gateway__port_resolve_physical project_path_gateway__port_write_report project_path_gateway__port_read_file
# 입력 포트: project_path_gateway__port_replace_data_file project_path_gateway__port_kind
# 입력 포트: project_path_gateway__port_read_stdin project_path_gateway__port_path_kinds project_path_gateway__port_data_file_writable
# 입력 포트: project_path_gateway__port_script_lines
# 출력 포트: project_path_gateway__out_violation project_path_gateway__out_missing project_path_gateway__out_outside
# 출력 포트: project_path_gateway__out_kind_mismatch project_path_gateway__out_list_violation

# 종류 KIND(dir, file)의 데이터 파일 절대경로를 출력한다.
project_path_gateway__app_data_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__domain_join "$1" "$(project_path_gateway__domain_layout_data_file "$2")"
)

# 데이터 파일들을 차례로 읽고 검증한다. $1: 앞 데이터 파일까지의 본 키 목록, 나머지: 종류와 데이터 파일 경로의 쌍을 읽는 순서대로.
# 유효한 항목마다 레코드 한 줄을 읽은 순서로 출력하고, 위반은 끝까지 모두 보고 포트로 보고한다. 반환: 0 유효, 3 규칙 위반.
# 파이프라인 오른쪽은 서브셸이라 본 키 목록을 밖으로 돌려줄 수 없으므로, 한 파일을 다 읽은 그 자리에서 다음 쌍을 같은 방식으로 이어 읽는다.
project_path_gateway__app_load_files() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	seen=$1
	kind=$2
	file=$3
	shift 3
	project_path_gateway__port_read_lines "$file" | {
		lineno=0
		bad=0
		while IFS= read -r line; do
			lineno=$((lineno + 1))
			record=$(project_path_gateway__domain_entry_parse_line "$kind" "$lineno" "$line")
			status=$?
			case $status in
			2) continue ;;
			0)
				if first=$(project_path_gateway__domain_seen_register "$seen" "$record"); then
					seen=$first
					printf '%s\n' "$record"
					continue
				fi
				code=duplicate_key
				;;
			*)
				code=$record
				first=
				;;
			esac
			key=$(project_path_gateway__domain_entry_line_key "$line")
			has_cr=0
			if project_path_gateway__domain_entry_line_has_cr "$line"; then
				has_cr=1
			fi
			project_path_gateway__out_violation "$file" "$lineno" "$code" "$key" "$first" "$has_cr" "$kind"
			bad=1
		done
		if [ "$#" -gt 0 ]; then
			project_path_gateway__app_load_files "$seen" "$@" || bad=1
		fi
		[ "$bad" -eq 0 ]
	} || return 3
	return 0
)

# 두 데이터 파일을 도구 배치의 종류 순서(디렉터리 → 파일)로 읽고 검증한다 (기능 007 research R-06).
# 유효한 항목마다 레코드 한 줄을 읽은 순서로 출력한다. 키 유일성은 두 파일을 합쳐 판정하고, 위반은 두 파일 모두 끝까지 보고한다.
# 읽기 전에 두 파일을 모두 확인하며, 읽을 수 없는 데이터 파일이 있으면 먼저 확인한 쪽의 경로를 끝 표지 방식으로 출력한다.
# 반환: 0 유효, 3 규칙 위반, 4 읽기 불가, 15 읽기 불가이고 1.x 데이터 파일이 있음 (research R-07).
project_path_gateway__app_load_entries() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	root=$1
	set --
	for kind in $(project_path_gateway__domain_layout_kinds); do
		file=$(project_path_gateway__app_data_file "$root" "$kind")
		if ! project_path_gateway__port_readable_file "$file"; then
			printf '%sx' "$file"
			legacy=$(project_path_gateway__domain_join "$root" "$(project_path_gateway__domain_layout_legacy_data_file)")
			project_path_gateway__port_readable_file "$legacy" && return 15
			return 4
		fi
		set -- "$@" "$kind" "$file"
	done
	project_path_gateway__app_load_files '' "$@"
)

# 런타임 초기화 흐름. 성공하면 루트를, 실패하면 문구에 쓸 상세 값을 끝 표지 방식으로 출력한다.
# 반환: 0 성공, 8 디렉터리 아님(상세: START_DIR), 5 경로 확인 실패(상세: START_DIR),
# 6 루트 표식 없음(상세: 물리 시작 디렉터리), 4·15 데이터 파일 읽기 불가(상세: 읽지 못한 데이터 파일 경로), 3 규칙 위반(상세 없음).
project_path_gateway__app_init() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if ! project_path_gateway__port_is_dir "$1"; then
		printf '%sx' "$1"
		return 8
	fi
	if ! start=$(project_path_gateway__port_physical_dir "$1"); then
		printf '%sx' "$1"
		return 5
	fi
	start=${start%x}
	marker=$(project_path_gateway__domain_layout_marker)
	if ! root=$(project_path_gateway__port_find_root "$start" "$marker"); then
		printf '%sx' "$start"
		return 6
	fi
	root=${root%x}
	records=$(project_path_gateway__app_load_entries "$root")
	status=$?
	case $status in
	0)
		printf '%sx' "$root"
		return 0
		;;
	4 | 15)
		printf '%s' "$records"
		return "$status"
		;;
	esac
	return 3
)

# 키에 등록된 경로를 루트와 결합해 출력한다. $1: 루트, $2: 종류, $3: KEY.
# 반환: 0 성공, 3 규칙 위반, 4·15 읽기 불가(상세: 데이터 파일 경로), 7 미등록 키, 14 다른 종류의 키.
project_path_gateway__app_lookup() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	records=$(project_path_gateway__app_load_entries "$1")
	status=$?
	if [ "$status" -ne 0 ]; then
		[ "$status" -eq 3 ] || printf '%s' "$records"
		return "$status"
	fi
	record=$(project_path_gateway__domain_entries_find "$records" "$3") || return 7
	[ "$(project_path_gateway__domain_entry_kind "$record")" = "$2" ] || return 14
	project_path_gateway__domain_join "$1" "$(project_path_gateway__domain_entry_path "$record")"
)

# 모든 항목의 존재(V-1), 루트 내부 여부(V-2), 실제 종류(V-3)를 읽은 순서대로 판정한다 (기능 007 research R-08).
# 앞 단계에서 실패한 항목은 뒤 단계를 보지 않고, 실패 항목은 보고 포트로 한 줄씩 보고한다.
# 끝에 "ok <통과 수>" 또는 "fail <실패 수>" 한 줄을 출력한다. 반환: 0 모두 통과, 1 실패 있음, 3·4·15 데이터 파일 오류(4·15 상세: 데이터 파일 경로).
project_path_gateway__app_verify() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	records=$(project_path_gateway__app_load_entries "$1")
	status=$?
	if [ "$status" -ne 0 ]; then
		[ "$status" -eq 3 ] || printf '%s' "$records"
		return "$status"
	fi
	project_path_gateway__domain_entries_fields "$records" | {
		passed=0
		failed=0
		while IFS= read -r kind && IFS= read -r key && IFS= read -r path; do
			full=$(project_path_gateway__domain_join "$1" "$path")
			if ! project_path_gateway__port_exists "$full" ||
				! physical=$(project_path_gateway__port_resolve_physical "$full"); then
				project_path_gateway__out_missing "$key" "$path"
				failed=$((failed + 1))
				continue
			fi
			physical=${physical%x}
			if ! project_path_gateway__domain_is_inside "$1" "$physical"; then
				project_path_gateway__out_outside "$key" "$path" "$physical"
				failed=$((failed + 1))
				continue
			fi
			if [ "$(project_path_gateway__port_kind "$physical")" != "$kind" ]; then
				project_path_gateway__out_kind_mismatch "$key" "$path" "$kind"
				failed=$((failed + 1))
				continue
			fi
			passed=$((passed + 1))
		done
		if [ "$failed" -gt 0 ]; then
			printf 'fail %s\n' "$failed"
			return 1
		fi
		printf 'ok %s\n' "$passed"
		return 0
	}
)

# 등록(add)·갱신(update) 흐름 (기능 004 research R-01, 기능 007 research R-04·R-05). $1: add 또는 update, $2: 종류, $3: 루트, $4: KEY, $5: PATH.
# 쓰기 대상은 종류의 데이터 파일 하나이고 다른 데이터 파일은 키 유일성 확인에만 읽는다 (기능 007 FR-023).
# 인자 규칙 위반이면 위반 코드를, 그 밖의 실패면 관련 데이터 파일 경로를 끝 표지 방식으로 출력한다.
# 반환: 0 성공, 9 인자 규칙 위반, 3·4·15 데이터 파일 오류, 10 이미 등록된 키, 7 미등록 키, 14 다른 종류의 키,
# 11 데이터 파일이 링크, 12 쓰기 권한 없음, 13 교체 실패.
project_path_gateway__app_edit() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	violation=$(project_path_gateway__domain_entry_violation "$2" "$4" "$5")
	if [ -n "$violation" ]; then
		printf '%s\n' "$violation"
		return 9
	fi
	records=$(project_path_gateway__app_load_entries "$3")
	status=$?
	if [ "$status" -ne 0 ]; then
		[ "$status" -eq 3 ] || printf '%s' "$records"
		return "$status"
	fi
	file=$(project_path_gateway__app_data_file "$3" "$2")
	printf '%sx' "$file"
	line=$(project_path_gateway__domain_entry_to_line "$4" "$5")
	case $1 in
	add)
		if record=$(project_path_gateway__domain_entries_find "$records" "$4"); then
			return 10
		fi
		content=$(project_path_gateway__port_read_file "$file") || return 4
		content=$(project_path_gateway__domain_append_entry "${content%x}" "$line")
		;;
	update)
		record=$(project_path_gateway__domain_entries_find "$records" "$4") || return 7
		[ "$(project_path_gateway__domain_entry_kind "$record")" = "$2" ] || return 14
		[ "$(project_path_gateway__domain_entry_path "$record")" = "$5" ] && return 0
		lineno=$(project_path_gateway__domain_entry_lineno "$record")
		content=$(project_path_gateway__port_read_file "$file") || return 4
		content=$(project_path_gateway__domain_replace_line "${content%x}" "$lineno" "$line") || return 13
		;;
	*) return 13 ;;
	esac
	project_path_gateway__port_replace_data_file "$file" "${content%x}"
	case $? in
	0) return 0 ;;
	1) return 11 ;;
	2) return 12 ;;
	esac
	return 13
)

# 데이터 파일 FILE 원문 끝에 블록(KEY=경로 줄을 LF로 이은 것)을 더해 바꾼다 (기능 008 research R-09 8단계).
# 줄을 하나씩 등록한 결과와 같다(append_entry가 원문 끝 LF를 보충한다). 반환: 0 성공, 4 읽기 실패, 11 링크, 12 쓰기 권한 없음, 13 교체 실패.
project_path_gateway__app_append_block() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	content=$(project_path_gateway__port_read_file "$1") || return 4
	content=$(project_path_gateway__domain_append_entry "${content%x}" "$2")
	project_path_gateway__port_replace_data_file "$1" "${content%x}"
	case $? in
	0) return 0 ;;
	1) return 11 ;;
	2) return 12 ;;
	esac
	return 13
)

# 일괄 등록 흐름 (기능 008 research R-09). $1: 루트, $2: 목록 파일 경로 또는 -(표준 입력).
# 목록 위반은 끝까지 모두 보고 포트로 보고하고 아무것도 쓰지 않는다. 등록할 항목이 있는 데이터 파일만 쓰기 전에 확인하고 디렉터리 → 파일 순서로 바꾼다.
# 성공하면 "디렉터리 수 파일 수 유지 수"를, 실패하면 상세 값을 끝 표지 방식으로 출력한다.
# 반환: 0 성공, 3·4·15 데이터 파일 오류(4·15 상세: 데이터 파일 경로), 16 목록 읽기 불가, 17 목록 위반(상세: 위반 수),
# 11 데이터 파일이 링크, 12 쓰기 권한 없음, 13 도구 디렉터리 쓰기 불가·교체 실패, 4 쓰기 직전 읽기 실패(상세: 데이터 파일 경로),
# 18 디렉터리 데이터 파일을 바꾼 뒤 파일 데이터 파일 쓰기 실패(상세: 파일 데이터 파일 경로).
project_path_gateway__app_add_list() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	records=$(project_path_gateway__app_load_entries "$1")
	status=$?
	if [ "$status" -ne 0 ]; then
		[ "$status" -eq 3 ] || printf '%s' "$records"
		return "$status"
	fi
	if [ "$2" = - ]; then
		text=$(project_path_gateway__port_read_stdin) || return 16
	else
		project_path_gateway__port_readable_file "$2" || return 16
		text=$(project_path_gateway__port_read_file "$2") || return 16
	fi
	items=$(printf '%s' "${text%x}" | {
		lineno=0
		while IFS= read -r line || [ -n "$line" ]; do
			lineno=$((lineno + 1))
			project_path_gateway__domain_entry_parse_list_line "$lineno" "$line"
		done
	})
	kinds=$(project_path_gateway__port_path_kinds "$(project_path_gateway__domain_entries_full_paths "$1" "$items")")
	checked=$(project_path_gateway__domain_entries_check_list "$records" "$items" "$kinds")
	violations=$(project_path_gateway__domain_entries_list_violations "$checked")
	if [ -n "$violations" ]; then
		# 마지막 위반의 빈 상세2는 명령 치환에서 사라지므로 상세2 읽기 실패는 빈 값으로 본다.
		printf '%s\n' "$violations" | {
			count=0
			while IFS= read -r lineno && IFS= read -r code && IFS= read -r key && IFS= read -r first; do
				IFS= read -r second || second=
				project_path_gateway__out_list_violation "$2" "$lineno" "$code" "$key" "$first" "$second"
				count=$((count + 1))
			done
			printf '%sx' "$count"
		}
		return 17
	fi
	dir_block=$(project_path_gateway__domain_entries_list_block "$checked" dir)
	file_block=$(project_path_gateway__domain_entries_list_block "$checked" file)
	dir_file=$(project_path_gateway__app_data_file "$1" dir)
	file_file=$(project_path_gateway__app_data_file "$1" file)
	for kind in $(project_path_gateway__domain_layout_kinds); do
		if [ "$kind" = dir ]; then
			[ -n "$dir_block" ] || continue
			file=$dir_file
		else
			[ -n "$file_block" ] || continue
			file=$file_file
		fi
		project_path_gateway__port_data_file_writable "$file"
		case $? in
		0) continue ;;
		1) status=11 ;;
		2) status=12 ;;
		*) status=13 ;;
		esac
		printf '%sx' "$file"
		return "$status"
	done
	if [ -n "$dir_block" ]; then
		project_path_gateway__app_append_block "$dir_file" "$dir_block"
		status=$?
		if [ "$status" -ne 0 ]; then
			printf '%sx' "$dir_file"
			return "$status"
		fi
	fi
	if [ -n "$file_block" ]; then
		project_path_gateway__app_append_block "$file_file" "$file_block"
		status=$?
		if [ "$status" -ne 0 ]; then
			printf '%sx' "$file_file"
			[ -n "$dir_block" ] && return 18
			return "$status"
		fi
	fi
	printf '%sx' "$(project_path_gateway__domain_entries_list_counts "$checked")"
	return 0
)

# 찾기 해석 단계 (기능 008 research R-06 3·4단계). 표준 입력: domain_scan_pick 출력(대상마다 번호, 상태, 경로, 절대경로 네 줄). $1: 루트.
# 대상마다 해석 결과 레코드를 출력한다. 있는 경로는 실제 위치가 루트 안인지와 경로 모양을 확인하고, 도구 파일은 내지 않는다.
project_path_gateway__app_scan_resolve() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	while IFS= read -r id && IFS= read -r state && IFS= read -r path; do
		IFS= read -r full || full=
		if [ "$state" != root ] && project_path_gateway__domain_layout_is_tool_file "$path"; then
			continue
		fi
		kind=$state
		cause=
		case $state in
		dir | file)
			if physical=$(project_path_gateway__port_resolve_physical "$full") &&
				project_path_gateway__domain_is_inside "$1" "${physical%x}"; then
				if cause=$(project_path_gateway__domain_path_violation "$path" "$state"); then
					status=ok
				else
					status=blocked
				fi
			else
				status=blocked
				cause=outside
			fi
			;;
		other)
			status=blocked
			cause=special
			;;
		none)
			kind=$(project_path_gateway__domain_scan_guess_kind "$path")
			status=missing
			;;
		*)
			kind=
			status=root
			;;
		esac
		project_path_gateway__domain_scan_resolution "$id" "$status" "$kind" "$cause" "$path"
	done
	return 0
)

# 찾기 흐름 (기능 008 research R-02~R-07). $1: 루트. 읽기만 하며 파일을 바꾸지 않는다.
# 성공하면 후보 스트림(data-model 3.4)을, 데이터 파일 읽기 불가면 데이터 파일 경로를 끝 표지 방식으로 출력한다.
# 반환: 0 성공, 3 데이터 파일 규칙 위반, 4·15 데이터 파일 읽기 불가.
project_path_gateway__app_scan() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	records=$(project_path_gateway__app_load_entries "$1")
	status=$?
	if [ "$status" -ne 0 ]; then
		[ "$status" -eq 3 ] || printf '%s' "$records"
		return "$status"
	fi
	lines=$(project_path_gateway__port_script_lines "$1")
	extracted=$(project_path_gateway__domain_scan_extract "$1" "$records" "$lines")
	kinds=$(project_path_gateway__port_path_kinds "$(project_path_gateway__domain_scan_probe_paths "$extracted")")
	resolved=$(project_path_gateway__domain_scan_pick "$extracted" "$kinds" | project_path_gateway__app_scan_resolve "$1")
	printf '%sx' "$(project_path_gateway__domain_scan_group "$extracted" "$resolved")"
	return 0
)

# 검증 리포트 본문을 리포트 파일에 저장한다. 본문 형식은 알지 않는다. 반환: 0 성공, 1 쓰기 실패 (기능 003).
project_path_gateway__app_write_report() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__port_write_report "$1" "$2"
)

# === 계층: 인프라 ===

# 시스템 포트(project_path_gateway__sys_*)만 파일 시스템에 접근한다. 본문은 명령 하나이며 다른 내부 함수를 호출하지 않는다.
# 포트(project_path_gateway__port_*)는 탐색·링크 추적 논리를 담고 환경 접근은 시스템 포트에 맡긴다.

# 디렉터리이면 반환 0.
project_path_gateway__port_is_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__sys_is_dir "$1"
)

# 디렉터리의 물리 경로를 끝 표지 방식으로 출력한다. 실패하면 반환 1.
project_path_gateway__port_physical_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__sys_physical_dir "$1"
)

# 일반 파일이고 읽을 수 있으면 반환 0.
project_path_gateway__port_readable_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__sys_is_file "$1" && project_path_gateway__sys_is_readable "$1"
)

# 파일의 각 줄을 개행을 붙여 출력한다. 마지막 줄에 개행이 없어도 출력한다.
project_path_gateway__port_read_lines() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__sys_read_lines "$1"
)

# 물리 시작 디렉터리부터 /까지 올라가며 루트 표식 파일이 일반 파일로 있는 가장 가까운 디렉터리를
# 끝 표지 방식으로 출력한다. 찾지 못하면 반환 1 (FR-002 4단계, research R-06). $2: 루트 기준 표식 상대경로.
project_path_gateway__port_find_root() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	dir=$1
	while :; do
		if project_path_gateway__sys_is_file "${dir%/}/$2"; then
			printf '%sx' "$dir"
			return 0
		fi
		[ "$dir" = / ] && return 1
		dir=${dir%/*}
		[ -n "$dir" ] || dir=/
	done
)

# 경로가 존재하면 반환 0. 심볼릭 링크는 최종 대상이 있어야 하며, 끊어진·순환 링크와 권한 부족은 거짓이다.
project_path_gateway__port_exists() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__sys_exists "$1"
)

# 경로의 종류를 한 줄로 출력한다: 디렉터리 dir, 일반 파일 file, 그 밖 other. 링크는 최종 대상으로 판정한다 (기능 007 research R-08).
project_path_gateway__port_kind() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if project_path_gateway__sys_is_dir "$1"; then
		printf 'dir\n'
	elif project_path_gateway__sys_is_file "$1"; then
		printf 'file\n'
	else
		printf 'other\n'
	fi
	return 0
)

# 심볼릭 링크를 모두 따라간 최종 물리 경로를 끝 표지 방식으로 출력한다. 실패하면 반환 1 (research R-05).
project_path_gateway__port_resolve_physical() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	current=$1
	count=0
	while :; do
		if project_path_gateway__sys_is_dir "$current"; then
			project_path_gateway__sys_physical_dir "$current"
			return $?
		fi
		case $current in
		*/*)
			parent=${current%/*}
			name=${current##*/}
			;;
		*)
			parent=.
			name=$current
			;;
		esac
		[ -n "$parent" ] || parent=/
		parent=$(project_path_gateway__sys_physical_dir "$parent") || return 1
		parent=${parent%x}
		current=${parent%/}/$name
		if ! project_path_gateway__sys_is_link "$current"; then
			printf '%sx' "$current"
			return 0
		fi
		count=$((count + 1))
		[ "$count" -le 40 ] || return 1
		target=$(project_path_gateway__sys_readlink "$current") || return 1
		target=${target%x}
		case $target in
		/*) current=$target ;;
		*) current=${parent%/}/$target ;;
		esac
	done
)

# 검증 리포트 본문을 같은 디렉터리 임시 파일(.ppg-report.<PID>.<이름>)에 쓴 뒤 제자리로 옮긴다. 대상이 디렉터리이거나
# 디렉터리를 가리키는 링크, 이름이 빈 경로이면 반환 1. 쓰기·옮기기에 실패하면 임시 파일을 지우고 반환 1 (기능 003 research R-03).
project_path_gateway__port_write_report() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	*/) return 1 ;;
	*/*) dir=${1%/*} ;;
	*) dir=. ;;
	esac
	if project_path_gateway__sys_is_dir "$1"; then
		return 1
	fi
	pid=$(project_path_gateway__sys_pid)
	temp="$dir/.ppg-report.$pid.${1##*/}"
	if project_path_gateway__sys_write_text "$temp" "$2" &&
		project_path_gateway__sys_move "$temp" "$1"; then
		return 0
	fi
	project_path_gateway__sys_remove "$temp"
	return 1
)

# 파일 원문을 끝 표지 방식으로 출력한다. 읽지 못하면 반환 1 (기능 004 research R-04).
project_path_gateway__port_read_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__sys_read_file "$1"
)

# 데이터 파일을 새 원문으로 바꾼다 (기능 004 research R-06). 링크이면 반환 1, 쓰기 권한이 없으면 반환 2.
# 원본 모드를 복사한 같은 디렉터리 임시 파일(.ppg-tmp.<PID>.<이름>)에 새 원문을 쓴 뒤 제자리로 옮긴다.
# 복사·쓰기·옮기기에 실패하면 임시 파일을 지우고 반환 3.
project_path_gateway__port_replace_data_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if project_path_gateway__sys_is_link "$1"; then
		return 1
	fi
	if ! project_path_gateway__sys_is_writable "$1"; then
		return 2
	fi
	pid=$(project_path_gateway__sys_pid)
	temp="${1%/*}/.ppg-tmp.$pid.${1##*/}"
	if project_path_gateway__sys_copy_preserve "$1" "$temp" &&
		project_path_gateway__sys_write_text "$temp" "$2" &&
		project_path_gateway__sys_move "$temp" "$1"; then
		return 0
	fi
	project_path_gateway__sys_remove "$temp"
	return 3
)

# 표준 입력 전체를 끝 표지 방식으로 출력한다. 읽지 못하면 반환 1 (기능 008 research R-09).
project_path_gateway__port_read_stdin() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__sys_read_stdin
)

# 경로 목록 PATHS(LF 구분)의 줄마다 종류를 한 줄씩 출력한다: 디렉터리 dir, 일반 파일 file, 그 밖에 존재 other, 없음·빈 줄 none.
# 링크는 최종 대상으로 판정한다(port_kind와 같음). 목록이 비면 아무것도 출력하지 않는다 (기능 008 research R-06).
project_path_gateway__port_path_kinds() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -n "$1" ] || return 0
	project_path_gateway__sys_path_kinds "$1"
)

# 데이터 파일을 바꿀 수 있는지 쓰기 전에 확인한다 (기능 008 research R-09 7단계).
# 반환: 0 가능, 1 링크, 2 파일 쓰기 권한 없음, 3 임시 파일을 만들 디렉터리 쓰기 권한 없음.
project_path_gateway__port_data_file_writable() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if project_path_gateway__sys_is_link "$1"; then
		return 1
	fi
	if ! project_path_gateway__sys_is_writable "$1"; then
		return 2
	fi
	if ! project_path_gateway__sys_is_writable "${1%/*}"; then
		return 3
	fi
	return 0
)

# 루트 ROOT 아래 찾기 대상 셸 스크립트를 이름 바이트 순서로 골라 찾기 스트림(domain_scan_script_lines 형식)을 이어 출력한다 (기능 008 research R-02).
# .sh 파일과, 실행 권한이 있고 첫 줄이 셸 shebang인 파일이 대상이다. 도구 파일, 이름에 TAB·CR이 든 파일, 읽을 수 없는 파일은 건너뛴다.
project_path_gateway__port_script_lines() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__sys_find_scripts "$1" | LC_ALL=C sort | while IFS= read -r file; do
		case $(project_path_gateway__domain_scan_file_class "$1" "$file") in
		script) ;;
		check)
			first=$(project_path_gateway__sys_read_first_line "$file") || continue
			project_path_gateway__domain_scan_is_shell_shebang "${first%x}" || continue
			;;
		*) continue ;;
		esac
		project_path_gateway__sys_is_readable "$file" || continue
		project_path_gateway__domain_scan_script_lines "$file" "$(project_path_gateway__sys_read_lines "$file")"
	done
	return 0
)

# 시스템 포트: 디렉터리이면 반환 0 (링크를 따라간다).
project_path_gateway__sys_is_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -d "$1" ]
)

# 시스템 포트: 일반 파일이면 반환 0 (링크를 따라간다).
project_path_gateway__sys_is_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -f "$1" ]
)

# 시스템 포트: 읽을 수 있으면 반환 0.
project_path_gateway__sys_is_readable() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -r "$1" ]
)

# 시스템 포트: 쓰기 권한이 있으면 반환 0.
project_path_gateway__sys_is_writable() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -w "$1" ]
)

# 시스템 포트: 존재하면 반환 0 (링크를 따라간다).
project_path_gateway__sys_exists() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -e "$1" ]
)

# 시스템 포트: 심볼릭 링크이면 반환 0 (따라가지 않는다).
project_path_gateway__sys_is_link() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -L "$1" ]
)

# 시스템 포트: 디렉터리의 물리 경로를 끝 표지 방식으로 출력한다. 실패하면 반환 1.
project_path_gateway__sys_physical_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	dir=$(cd -P -- "$1" 2>/dev/null && pwd -P && printf x) || return 1
	dir=${dir%x}
	printf '%sx' "${dir%?}"
)

# 시스템 포트: 심볼릭 링크 대상 문자열을 끝 표지 방식으로 출력한다. 실패하면 반환 1.
project_path_gateway__sys_readlink() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	target=$(readlink -- "$1" && printf x) || return 1
	target=${target%x}
	printf '%sx' "${target%?}"
)

# 시스템 포트: 파일의 각 줄을 개행을 붙여 출력한다. 마지막 줄에 개행이 없어도 출력한다.
project_path_gateway__sys_read_lines() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	while IFS= read -r line || [ -n "$line" ]; do
		printf '%s\n' "$line"
	done <"$1"
)

# 시스템 포트: 파일 내용을 끝 표지 방식으로 출력한다. 읽지 못하면 반환 1.
project_path_gateway__sys_read_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	text=$(cat -- "$1" 2>/dev/null && printf x) || return 1
	printf '%s' "$text"
)

# 시스템 포트: 현재 셸의 프로세스 ID를 한 줄로 출력한다.
project_path_gateway__sys_pid() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s\n' "$$"
)

# 시스템 포트: 내용 문자열을 파일에 그대로 쓴다. 실패하면 반환 1.
project_path_gateway__sys_write_text() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	{ printf '%s' "$2" >"$1"; } 2>/dev/null
)

# 시스템 포트: 원본 파일을 모드와 함께 대상에 복사한다. 실패하면 반환 1.
project_path_gateway__sys_copy_preserve() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	cp -p -- "$1" "$2" 2>/dev/null
)

# 시스템 포트: 원본을 대상 자리로 옮긴다(대상이 있으면 바꾼다). 실패하면 반환 1.
project_path_gateway__sys_move() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	mv -f -- "$1" "$2" 2>/dev/null
)

# 시스템 포트: 파일을 지운다. 없으면 성공이다.
project_path_gateway__sys_remove() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	rm -f -- "$1" 2>/dev/null
)

# 시스템 포트: 경로 목록의 줄마다 dir, file, other, none을 출력한다(링크를 따라간다).
project_path_gateway__sys_path_kinds() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s\n' "$1" | while IFS= read -r path; do
		if [ -z "$path" ]; then
			printf 'none\n'
		elif [ -d "$path" ]; then
			printf 'dir\n'
		elif [ -f "$path" ]; then
			printf 'file\n'
		elif [ -e "$path" ]; then
			printf 'other\n'
		else
			printf 'none\n'
		fi
	done
)

# 시스템 포트: 표준 입력 전체를 끝 표지 방식으로 출력한다. 읽지 못하면 반환 1.
project_path_gateway__sys_read_stdin() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	text=$(cat && printf x) || return 1
	printf '%s' "$text"
)

# 시스템 포트: ROOT 아래 일반 파일 중 이름이 .sh로 끝나거나 소유자 실행 권한이 있는 것을 한 줄에 하나씩 출력한다.
# 버전 관리 디렉터리와 이름에 LF가 든 항목 아래는 보지 않고, 링크 디렉터리 안으로 들어가지 않으며, 읽을 수 없는 디렉터리는 건너뛴다.
project_path_gateway__sys_find_scripts() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	nl='
'
	find "$1" \( -name '.gi[t]' -o -name "*$nl*" \) -prune -o -type f \( -name '*.sh' -o -perm -100 \) -print 2>/dev/null
	return 0
)

# 시스템 포트: 파일의 첫 줄(끝 LF 제외, NUL 바이트 제거)을 끝 표지 방식으로 출력한다. 읽지 못하면 반환 1.
project_path_gateway__sys_read_first_line() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	line=$(head -n 1 -- "$1" 2>/dev/null | tr -d '\000' && printf x) || return 1
	line=${line%x}
	nl='
'
	printf '%sx' "${line%"$nl"}"
)

# === 계층: 인터페이스 ===
# 공개 함수 본문은 입력 검사 → 유스케이스 호출 → 결과 매핑(if_*_result) 순서다 (기능 005 FR-043).
# 종류별 공개 함수는 같은 흐름을 종류 인자로 공유한다(if_lookup, if_edit). 출력 포트 구현(out_*)은 애플리케이션이 호출하는 보고 문구를 정한다.

# 공통 오류 출력: project-path-gateway: FUNC: MESSAGE
project_path_gateway__if_error() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf 'project-path-gateway: %s: %s\n' "$1" "$2" >&2
)

# 종류 위반 원인 코드의 문구를 출력한다(끝 LF 없음). 데이터 파일 위반 보고와 등록·갱신 인자 오류가 같이 쓴다 (기능 007 contracts/data-files.md 3절).
# $1: 원인 코드, $2: 문구 끝에 붙일 값. 종류 위반이 아니면 반환 1.
project_path_gateway__if_kind_violation_message() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	not_dir_path) printf '디렉터리 경로가 파일 모양입니다(확장자가 있거나 .으로 시작): %s' "$2" ;;
	not_file_path) printf '파일 경로가 파일 모양이 아닙니다(이름.확장자 또는 .으로 시작하는 이름, 끝 / 없음): %s' "$2" ;;
	*) return 1 ;;
	esac
	return 0
)

# 데이터 파일 줄과 일괄 등록 목록 줄이 함께 쓰는 줄 위반 문구를 출력한다(끝 LF 없음) (기능 008 research R-13).
# $1: 원인 코드, $2: 줄의 키. 공통 원인 코드가 아니면 출력 없이 반환 1.
project_path_gateway__if_line_violation_message() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	no_separator) printf '%s' 'KEY=경로 형식이 아닙니다' ;;
	invalid_key) printf '키 형식이 잘못되었습니다(대문자로 시작, 대문자·숫자·_만 허용): %s' "$2" ;;
	empty_path) printf '경로가 비어 있습니다: %s' "$2" ;;
	absolute_path) printf '경로는 /로 시작할 수 없습니다: %s' "$2" ;;
	parent_segment) printf '경로에 .. 세그먼트를 쓸 수 없습니다: %s' "$2" ;;
	carriage_return) printf '%s' 'CR 문자가 포함되어 있습니다(CRLF 줄 끝인지 확인하세요)' ;;
	not_dir_path | not_file_path) project_path_gateway__if_kind_violation_message "$1" "$2" ;;
	*) return 1 ;;
	esac
	return 0
)

# 출력 포트 구현: 데이터 파일 위반 보고 (기능 001 contracts/library-api.md 6절, 기능 007 contracts/data-files.md 3절).
# $1: 데이터 파일, $2: 줄 번호, $3: 원인 코드, $4: 줄의 키, $5: 중복 키가 처음 정의된 위치(종류/줄번호), $6: CR 있음(1), $7: 이 데이터 파일의 종류.
project_path_gateway__out_violation() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $3 in
	duplicate_key)
		first_kind=${5%%/*}
		if [ "$first_kind" = "$7" ]; then
			message="중복된 키입니다(${5#*/}번째 줄에서 정의됨): $4"
		else
			first_file=$(project_path_gateway__domain_layout_data_file "$first_kind")
			message="중복된 키입니다(${first_file##*/} ${5#*/}번째 줄에서 정의됨): $4"
		fi
		;;
	*) message=$(project_path_gateway__if_line_violation_message "$3" "$4") || message="알 수 없는 위반입니다: $3" ;;
	esac
	if [ "$6" = 1 ] && [ "$3" != carriage_return ]; then
		message="$message (CRLF 줄 끝인지 확인하세요)"
	fi
	printf 'project-path-gateway: %s:%s: %s\n' "$1" "$2" "$message" >&2
)

# 출력 포트 구현: 검증 누락 보고.
project_path_gateway__out_missing() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf 'project-path-gateway: 누락: %s=%s\n' "$1" "$2" >&2
)

# 출력 포트 구현: 검증 루트 밖 보고.
project_path_gateway__out_outside() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf 'project-path-gateway: 루트 밖: %s=%s -> %s\n' "$1" "$2" "$3" >&2
)

# 출력 포트 구현: 검증 종류 불일치 보고 (기능 007 contracts/library-api.md 5절). $1: KEY, $2: PATH, $3: 항목 종류.
project_path_gateway__out_kind_mismatch() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$3" = file ]; then
		printf 'project-path-gateway: 종류 불일치: %s=%s (일반 파일이 아님)\n' "$1" "$2" >&2
	else
		printf 'project-path-gateway: 종류 불일치: %s=%s (디렉터리가 아님)\n' "$1" "$2" >&2
	fi
)

# 출력 포트 구현: 일괄 등록 목록 위반 보고 (기능 008 contracts/library-api.md 3절).
# $1: 목록 이름(파일 경로 또는 -), $2: 줄 번호, $3: 원인 코드, $4: 줄의 키, $5: 상세1, $6: 상세2 (기능 008 data-model 2.2).
project_path_gateway__out_list_violation() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $3 in
	kind_mismatch)
		case $6 in
		file) message="경로가 디렉터리 모양이지만 실제로는 일반 파일입니다(파일 항목은 이름.확장자 또는 .으로 시작하는 이름): $4" ;;
		dir) message="경로가 파일 모양이지만 실제로는 디렉터리입니다(디렉터리 항목은 확장자가 없고 .으로 시작하지 않는 이름): $4" ;;
		*) message="경로가 디렉터리나 일반 파일이 아닙니다: $4" ;;
		esac
		;;
	duplicate_key) message="목록 안에서 중복된 키입니다($5번째 줄에서 정의됨): $4" ;;
	key_conflict)
		file=$(project_path_gateway__domain_layout_data_file "$5")
		message="이미 다른 경로로 등록된 키입니다(${file##*/}: $6): $4"
		;;
	*)
		message=$(project_path_gateway__if_line_violation_message "$3" "$4") || message="알 수 없는 위반입니다: $3"
		if [ "$5" = 1 ] && [ "$3" != carriage_return ]; then
			message="$message (CRLF 줄 끝인지 확인하세요)"
		fi
		;;
	esac
	printf 'project-path-gateway: %s:%s: %s\n' "$1" "$2" "$message" >&2
)

# 미초기화이면 문구를 출력하고 반환 1. $1: 공개 함수 이름.
project_path_gateway__if_require_init() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ]; then
		project_path_gateway__if_error "$1" '초기화되지 않았습니다. project_path_gateway_init을 먼저 호출하세요'
		return 1
	fi
	return 0
)

# 데이터 파일 읽기 불가 문구를 출력한다 (기능 007 contracts/library-api.md 2·3절).
# $1: 공개 함수 이름, $2: 내부 코드(4 또는 15), $3: 끝 표지가 붙은 읽지 못한 데이터 파일 경로. 다른 코드면 출력하지 않는다.
# 15이면 같은 도구 디렉터리의 1.x 데이터 파일을 옮기라는 안내 줄을 덧붙인다.
project_path_gateway__if_data_file_fail() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $2 in
	4 | 15) ;;
	*) return 0 ;;
	esac
	file=${3%x}
	project_path_gateway__if_error "$1" "데이터 파일을 읽을 수 없습니다: $file"
	if [ "$2" = 15 ]; then
		legacy=$(project_path_gateway__domain_layout_legacy_data_file)
		project_path_gateway__if_error "$1" "이전 형식 데이터 파일이 있습니다: ${file%/*}/${legacy##*/}. README의 \"1.x 프로젝트 옮기기\" 절차로 항목을 옮기세요"
	fi
	return 0
)

# 종류 불일치(내부 코드 14) 문구를 출력한다 (기능 007 contracts/library-api.md 2·4절). $1: 공개 함수 이름, $2: 함수 종류, $3: KEY.
project_path_gateway__if_kind_mismatch() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$2" = file ]; then
		project_path_gateway__if_error "$1" "파일 키가 아닙니다(디렉터리 데이터 파일에 등록됨): $3"
	else
		project_path_gateway__if_error "$1" "디렉터리 키가 아닙니다(파일 데이터 파일에 등록됨): $3"
	fi
)

# 결과 매핑: 런타임 초기화 실패 문구를 출력하고 반환 2. $1: 내부 코드, $2: 끝 표지가 붙은 상세 값.
project_path_gateway__if_init_result() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	detail=${2%x}
	case $1 in
	8) project_path_gateway__if_error project_path_gateway_init "디렉터리가 아닙니다: $detail" ;;
	5) project_path_gateway__if_error project_path_gateway_init "경로를 확인할 수 없습니다: $detail" ;;
	6) project_path_gateway__if_error project_path_gateway_init "루트 표식 파일($(project_path_gateway__domain_layout_marker))을 찾지 못했습니다: ${detail}부터 /까지" ;;
	4 | 15) project_path_gateway__if_data_file_fail project_path_gateway_init "$1" "$2" ;;
	3) ;;
	*) project_path_gateway__if_error project_path_gateway_init "알 수 없는 오류입니다(코드 $1)" ;;
	esac
	return 2
)

# 결과 매핑: 조회. $1: 공개 함수 이름, $2: 함수 종류, $3: 내부 코드, $4: 결과(경로 또는 상세 값), $5: KEY. 반환 0 또는 2.
project_path_gateway__if_lookup_result() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $3 in
	0)
		printf '%s\n' "$4"
		return 0
		;;
	7) project_path_gateway__if_error "$1" "등록되지 않은 키입니다: $5" ;;
	14) project_path_gateway__if_kind_mismatch "$1" "$2" "$5" ;;
	*) project_path_gateway__if_data_file_fail "$1" "$3" "$4" ;;
	esac
	return 2
)

# 조회 공개 함수 공통 흐름 (기능 007 contracts/library-api.md 2절). $1: 공개 함수 이름, $2: 함수 종류, 나머지: 공개 함수 인자.
project_path_gateway__if_lookup() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	func=$1
	kind=$2
	shift 2
	if [ "$#" -ne 1 ]; then
		project_path_gateway__if_error "$func" '인자는 KEY 1개여야 합니다'
		return 2
	fi
	project_path_gateway__if_require_init "$func" || return 2
	result=$(project_path_gateway__app_lookup "$PROJECT_PATH_GATEWAY_ROOT" "$kind" "$1")
	project_path_gateway__if_lookup_result "$func" "$kind" "$?" "$result" "$1"
)

# 결과 매핑: 검증 (기능 003 research R-02, 기능 005 research R-08). $1: 내부 코드, $2: 애플리케이션의 stdout·stderr를 합친 출력,
# $3: 루트, $4(있으면): 리포트 파일. 통과 문구는 stdout, 누락·루트 밖·종류 불일치·실패 문구는 stderr로 내고 리포트에 같은 줄을 저장한다.
# 반환: 0 통과, 1 검증 실패, 2 오류.
project_path_gateway__if_verify_result() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	nl='
'
	case $1 in
	0)
		body="project-path-gateway: 검증 통과 ${2#ok }"
		body="${body%"$nl"}건$nl"
		printf '%s' "$body"
		;;
	1)
		last=${2%"$nl"}
		summary=${last##*"$nl"}
		body="${last%"$summary"}project-path-gateway: 검증 실패 ${summary#fail }건$nl"
		printf '%s' "$body" >&2
		;;
	4 | 15)
		project_path_gateway__if_data_file_fail project_path_gateway_verify "$1" "$2"
		return 2
		;;
	*)
		printf '%s' "$2" >&2
		return 2
		;;
	esac
	if [ "$#" -ge 4 ] && ! project_path_gateway__app_write_report "$4" "$body"; then
		project_path_gateway__if_error project_path_gateway_verify "리포트 파일을 쓸 수 없습니다: $4"
		return 2
	fi
	[ "$1" = 0 ] && return 0
	return 1
)

# 결과 매핑: 등록·갱신 (기능 004 contracts/library-api-add-update.md 2절, 기능 007 contracts/library-api.md 4절).
# 성공이면 반환 0, 실패면 문구를 출력하고 반환 2.
# $1: 공개 함수 이름, $2: 함수 종류, $3: 내부 코드, $4: 상세(위반 코드 또는 끝 표지가 붙은 데이터 파일 경로), $5: KEY, $6: PATH.
project_path_gateway__if_edit_result() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ "$3" = 0 ] && return 0
	file=${4%x}
	case $3 in
	9)
		case $4 in
		invalid_key) message="키 형식이 잘못되었습니다(대문자로 시작, 대문자·숫자·_만 허용): $5" ;;
		empty_path) message='경로가 비어 있습니다' ;;
		absolute_path) message="경로는 /로 시작할 수 없습니다: $6" ;;
		parent_segment) message="경로에 .. 세그먼트를 쓸 수 없습니다: $6" ;;
		carriage_return) message='경로에 CR 문자를 쓸 수 없습니다' ;;
		line_feed) message='경로에 LF 문자를 쓸 수 없습니다' ;;
		not_dir_path | not_file_path) message=$(project_path_gateway__if_kind_violation_message "$4" "$6") ;;
		*) message="알 수 없는 위반입니다: $4" ;;
		esac
		;;
	3) return 2 ;;
	4 | 15)
		project_path_gateway__if_data_file_fail "$1" "$3" "$4"
		return 2
		;;
	7) message="등록되지 않은 키입니다: $5" ;;
	10) message="이미 등록된 키입니다: $5" ;;
	14)
		project_path_gateway__if_kind_mismatch "$1" "$2" "$5"
		return 2
		;;
	11) message="데이터 파일이 심볼릭 링크라 바꿀 수 없습니다: $file" ;;
	12) message="데이터 파일에 쓰기 권한이 없습니다: $file" ;;
	13) message="데이터 파일을 쓸 수 없습니다: $file" ;;
	*) message="알 수 없는 오류입니다(코드 $3)" ;;
	esac
	project_path_gateway__if_error "$1" "$message"
	return 2
)

# 등록·갱신 공개 함수 공통 흐름 (기능 004, 기능 007 contracts/library-api.md 4절).
# $1: add 또는 update, $2: 공개 함수 이름, $3: 함수 종류, 나머지: 공개 함수 인자.
project_path_gateway__if_edit() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	op=$1
	func=$2
	kind=$3
	shift 3
	if [ "$#" -ne 2 ]; then
		project_path_gateway__if_error "$func" '인자는 KEY와 PATH 2개여야 합니다'
		return 2
	fi
	project_path_gateway__if_require_init "$func" || return 2
	detail=$(project_path_gateway__app_edit "$op" "$kind" "$PROJECT_PATH_GATEWAY_ROOT" "$1" "$2")
	project_path_gateway__if_edit_result "$func" "$kind" "$?" "$detail" "$1" "$2"
)

# 결과 매핑: 일괄 등록 (기능 008 contracts/library-api.md 2절). $1: 내부 코드, $2: 끝 표지가 붙은 상세 값, $3: LIST.
# 성공이면 요약 한 줄을 stdout에 내고 반환 0, 실패면 문구를 출력하고 반환 2. 3·4·15·11·12·13은 등록 결과 매핑과 같은 문구다.
project_path_gateway__if_add_list_result() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	detail=${2%x}
	case $1 in
	0)
		dirs=${detail%% *}
		rest=${detail#* }
		printf 'project-path-gateway: 일괄 등록: 디렉터리 %s건, 파일 %s건, 유지 %s건\n' "$dirs" "${rest%% *}" "${rest#* }"
		return 0
		;;
	16)
		if [ "$3" = - ]; then
			project_path_gateway__if_error project_path_gateway_add_list '표준 입력에서 목록을 읽을 수 없습니다'
		else
			project_path_gateway__if_error project_path_gateway_add_list "목록 파일을 읽을 수 없습니다: $3"
		fi
		;;
	17) project_path_gateway__if_error project_path_gateway_add_list "목록 위반 ${detail}건이 있어 아무것도 등록하지 않았습니다" ;;
	18)
		dirs=$(project_path_gateway__domain_layout_data_file dir)
		project_path_gateway__if_error project_path_gateway_add_list "데이터 파일을 쓸 수 없습니다: $detail (이미 바뀐 데이터 파일: ${detail%/*}/${dirs##*/})"
		;;
	*) project_path_gateway__if_edit_result project_path_gateway_add_list '' "$1" "$2" '' '' ;;
	esac
	return 2
)

# 결과 매핑: 찾기 (기능 008 contracts/library-api.md 1절, contracts/scan-output.md). $1: 내부 코드, $2: 끝 표지가 붙은 후보 스트림 또는 상세 값, $3: 루트.
# 성공이면 찾기 결과 목록을 stdout에 내고 반환 0, 실패면 문구를 출력하고 반환 2. 결과의 줄은 모두 데이터 파일 줄 문법(KEY=경로, 주석, 빈 줄)을 따른다.
project_path_gateway__if_scan_result() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	0) ;;
	3) return 2 ;;
	4 | 15)
		project_path_gateway__if_data_file_fail project_path_gateway_scan "$1" "$2"
		return 2
		;;
	*)
		project_path_gateway__if_error project_path_gateway_scan "알 수 없는 오류입니다(코드 $1)"
		return 2
		;;
	esac
	printf '# project-path-gateway 찾기 결과 (루트: %s)\n' "$3"
	printf '# 이 목록은 project_path_gateway_add_list 입력으로 쓸 수 있습니다. 등록하지 않을 줄은 지우고 키 이름은 고쳐도 됩니다.\n'
	printf '%s\n' "${2%x}" | LC_ALL=C awk '
	BEGIN {
		FS = "\n"
		title["new"] = "새 후보"
		title["registered"] = "이미 등록"
		title["blocked"] = "등록 불가"
		title["missing"] = "확인 필요"
		title["root"] = "루트 참조"
		kname["dir"] = "디렉터리"
		kname["file"] = "파일"
		kname["other"] = "그 밖"
		cause["not_file_path"] = "파일 모양이 아닙니다(이름.확장자 또는 .으로 시작하는 이름). 상위 디렉터리를 디렉터리 항목으로 등록하고 이름을 붙여 쓰세요"
		cause["not_dir_path"] = "디렉터리 모양이 아닙니다(확장자가 있거나 .으로 시작). 상위 디렉터리를 디렉터리 항목으로 등록하고 이름을 붙여 쓰세요"
		cause["outside"] = "실제 위치가 루트 밖이거나 확인할 수 없습니다"
		cause["special"] = "디렉터리나 일반 파일이 아닙니다"
		trailer = ""
		cur = ""
	}
	function tab_field(s, n,   i, j) {
		for (i = 1; i != n; i++) s = substr(s, index(s, "\t") + 1)
		j = index(s, "\t")
		return j ? substr(s, 1, j - 1) : s
	}
	function tab_rest(s, n,   i) {
		for (i = 0; i != n; i++) s = substr(s, index(s, "\t") + 1)
		return s
	}
	function flush() {
		if (trailer != "") print trailer
		trailer = ""
	}
	function calls(info,   n, k, r, out, regs) {
		n = split(info, regs, " ")
		out = ""
		for (k = 1; k != n + 1; k++) {
			r = regs[k]
			out = out ((k == 1) ? "" : ", ") "project_path_gateway_" substr(r, 1, index(r, ":") - 1) " " substr(r, index(r, ":") + 1)
		}
		return out
	}
	substr($1, 1, 2) == "N\t" {
		cnt["new"] = tab_field($1, 3)
		cnt["registered"] = tab_field($1, 4)
		cnt["blocked"] = tab_field($1, 5)
		cnt["missing"] = tab_field($1, 6)
		cnt["root"] = tab_field($1, 7)
		printf "# 요약: 스크립트 %d개, 새 후보 %d, 이미 등록 %d, 등록 불가 %d, 확인 필요 %d, 루트 참조 %d\n", tab_field($1, 2), cnt["new"], cnt["registered"], cnt["blocked"], cnt["missing"], cnt["root"]
		next
	}
	substr($1, 1, 2) == "C\t" {
		flush()
		cls = tab_field($1, 2)
		kind = tab_field($1, 3)
		info = tab_field($1, 4)
		path = tab_rest($1, 4)
		if (cls != cur) {
			cur = cls
			printf "\n# == %s (%d) ==\n", title[cls], cnt[cls]
		}
		if (cls == "new") {
			printf "# %s %s\n", kname[kind], path
			trailer = info "=" path
		} else if (cls == "registered") {
			printf "# %s %s: %s\n", kname[kind], path, calls(info)
		} else if (cls == "blocked") {
			printf "# %s %s: %s\n", kname[kind], path, cause[info]
		} else if (cls == "missing") {
			printf "# %s(모양으로 추정) %s: 프로젝트에 없습니다. 등록하려면 아래 줄의 #을 지우세요\n", kname[kind], path
			trailer = "#" info "=" path
		} else {
			print "# 루트 자체를 가리킵니다. 키로 등록하지 말고 project_path_gateway_init이 정한 PROJECT_PATH_GATEWAY_ROOT를 쓰세요"
		}
		next
	}
	substr($1, 1, 2) == "@\t" {
		printf "#   %s:%s: %s%s\n", tab_field($1, 2), tab_field($1, 3), tab_rest($1, 4), (tab_field($1, 4) == "a") ? " (절대경로)" : ""
	}
	END { flush() }
	'
	return 0
)

# 공개 함수: 런타임 초기화 (contracts/library-api.md 3절).
# 호출 셸 변수 PROJECT_PATH_GATEWAY_ROOT를 설정·해제해야 하므로 서브셸 본문을 쓰지 않는다.
# 본문에서는 다른 변수를 만들지 않고, 명령 치환 대입은 if 조건 안에서만 수행한다. 매핑 결과는 함수 인자 자리에 받아 돌려준다.
project_path_gateway_init() {
	if [ "$#" -gt 1 ]; then
		project_path_gateway__if_error project_path_gateway_init '인자는 0개 또는 1개여야 합니다'
		unset PROJECT_PATH_GATEWAY_ROOT
		return 2
	fi
	if [ "$#" -eq 1 ]; then
		case $1 in
		/*) ;;
		*)
			project_path_gateway__if_error project_path_gateway_init "절대경로가 아닙니다: $1"
			unset PROJECT_PATH_GATEWAY_ROOT
			return 2
			;;
		esac
	fi
	if PROJECT_PATH_GATEWAY_ROOT=$(project_path_gateway__app_init "${1-.}"); then
		PROJECT_PATH_GATEWAY_ROOT=${PROJECT_PATH_GATEWAY_ROOT%x}
		return 0
	else
		project_path_gateway__if_init_result "$?" "${PROJECT_PATH_GATEWAY_ROOT-}"
	fi
	set -- "$?"
	unset PROJECT_PATH_GATEWAY_ROOT
	return "$1"
}

# 공개 함수: 등록 경로 검증 (contracts/library-api.md 5절, 기능 003 REPORT_FILE 선택 인자, 기능 007 종류 확인).
project_path_gateway_verify() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$#" -gt 1 ]; then
		project_path_gateway__if_error project_path_gateway_verify '인자는 0개 또는 REPORT_FILE 1개여야 합니다'
		return 2
	fi
	if [ "$#" -eq 1 ] && [ -z "$1" ]; then
		project_path_gateway__if_error project_path_gateway_verify '리포트 파일 경로가 비어 있습니다'
		return 2
	fi
	project_path_gateway__if_require_init project_path_gateway_verify || return 2
	captured=$(project_path_gateway__app_verify "$PROJECT_PATH_GATEWAY_ROOT" 2>&1
		printf 'x%s' "$?")
	project_path_gateway__if_verify_result "${captured##*x}" "${captured%x*}" "$PROJECT_PATH_GATEWAY_ROOT" "$@"
)

# 공개 함수: 디렉터리 키를 절대경로로 조회 (기능 007 contracts/library-api.md 2절).
project_path_gateway_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__if_lookup project_path_gateway_dir dir "$@"
)

# 공개 함수: 파일 키를 절대경로로 조회 (기능 007 contracts/library-api.md 2절).
project_path_gateway_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__if_lookup project_path_gateway_file file "$@"
)

# 공개 함수: 디렉터리 항목 등록 (기능 007 contracts/library-api.md 4절). 키가 어느 데이터 파일에든 있으면 반환 2.
project_path_gateway_add_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__if_edit add project_path_gateway_add_dir dir "$@"
)

# 공개 함수: 파일 항목 등록 (기능 007 contracts/library-api.md 4절). 키가 어느 데이터 파일에든 있으면 반환 2.
project_path_gateway_add_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__if_edit add project_path_gateway_add_file file "$@"
)

# 공개 함수: 디렉터리 항목 갱신 (기능 007 contracts/library-api.md 4절). 키가 없거나 파일 키이면 반환 2.
project_path_gateway_update_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__if_edit update project_path_gateway_update_dir dir "$@"
)

# 공개 함수: 파일 항목 갱신 (기능 007 contracts/library-api.md 4절). 키가 없거나 디렉터리 키이면 반환 2.
project_path_gateway_update_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__if_edit update project_path_gateway_update_file file "$@"
)

# 공개 함수: 경로 목록 일괄 등록 (기능 008 contracts/library-api.md 2절). LIST가 -이면 표준 입력에서 읽는다.
# 디렉터리 모양 경로는 디렉터리 데이터 파일에, 파일 모양 경로는 파일 데이터 파일에 목록 순서대로 더한다. 위반이 하나라도 있으면 아무것도 쓰지 않는다.
project_path_gateway_add_list() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$#" -ne 1 ]; then
		project_path_gateway__if_error project_path_gateway_add_list '인자는 LIST 1개여야 합니다'
		return 2
	fi
	if [ -z "$1" ]; then
		project_path_gateway__if_error project_path_gateway_add_list '목록 파일 경로가 비어 있습니다'
		return 2
	fi
	project_path_gateway__if_require_init project_path_gateway_add_list || return 2
	detail=$(project_path_gateway__app_add_list "$PROJECT_PATH_GATEWAY_ROOT" "$1")
	project_path_gateway__if_add_list_result "$?" "$detail" "$1"
)

# 공개 함수: 하드코딩된 경로 찾기 (기능 008 contracts/library-api.md 1절). 루트 아래 셸 스크립트를 읽기만 하고 아무 파일도 바꾸지 않는다.
# 결과는 project_path_gateway_add_list 입력으로 그대로 쓸 수 있는 목록이다(contracts/scan-output.md).
project_path_gateway_scan() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$#" -ne 0 ]; then
		project_path_gateway__if_error project_path_gateway_scan '인자를 받지 않습니다'
		return 2
	fi
	project_path_gateway__if_require_init project_path_gateway_scan || return 2
	detail=$(project_path_gateway__app_scan "$PROJECT_PATH_GATEWAY_ROOT")
	project_path_gateway__if_scan_result "$?" "$detail" "$PROJECT_PATH_GATEWAY_ROOT"
)
