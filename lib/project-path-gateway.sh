# project-path-gateway 0.1.0
#
# 프로젝트 경로 게이트웨이 라이브러리.
# 호출 셸에서 이 파일을 불러온(source) 뒤 공개 함수 세 개를 사용한다.
#
#   project_path_gateway_init [START_DIR]  루트 표식 파일을 찾아 루트를 한 번 계산한다
#   project_path_gateway_get KEY           키에 등록된 경로를 루트 기준 절대경로로 출력한다
#   project_path_gateway_verify            등록된 모든 경로의 존재와 루트 내부 여부를 확인한다
#
# 반환값: 0 성공, 1 검증 실패, 2 인자 오류·미초기화·루트 오류·데이터 파일 오류·미등록 키.
#
# 구조: 도메인 → 애플리케이션 → 인프라 → 인터페이스 네 구획으로 나눈다.
# project_path_gateway_init 외의 모든 함수는 서브셸 본문으로 정의해 호출 셸 상태를 바꾸지 않고,
# 본문 첫 줄에서 셸 옵션, IFS, CDPATH를 기본 상태로 되돌린다.
# 경로를 명령 치환으로 전달하는 함수는 끝 개행이 사라지지 않도록 값 뒤에 표지 문자 x를 붙인다.
# 내부 결과 코드: 3 데이터 파일 규칙 위반, 4 데이터 파일 읽기 불가, 5 경로 확인 실패,
# 6 루트 표식 파일 없음, 7 미등록 키, 8 디렉터리가 아님.

# === 계층: 도메인 ===

# 키 규칙을 만족하면 반환 0. 범위 괄호식 대신 문자 목록을 명시해 로캘과 무관하게 판정한다.
project_path_gateway__domain_is_valid_key() (
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

# 줄에 CR 문자가 있으면 반환 0.
project_path_gateway__domain_has_cr() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	cr=$(printf '\r')
	case $1 in
	*"$cr"*) return 0 ;;
	esac
	return 1
)

# 경로 규칙 위반 원인 코드를 출력한다. 위반이 없으면 아무것도 출력하지 않는다.
project_path_gateway__domain_path_violation() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	'')
		printf 'empty_path\n'
		return 0
		;;
	/*)
		printf 'absolute_path\n'
		return 0
		;;
	esac
	case /$1/ in
	*/../*)
		printf 'parent_segment\n'
		return 0
		;;
	esac
	if project_path_gateway__domain_has_cr "$1"; then
		printf 'carriage_return\n'
	fi
	return 0
)

# 줄을 분류해 ignore, entry 또는 위반 원인 코드를 출력한다 (data-model 1.5).
# 중복 키 검사는 파일 전체 상태가 필요하므로 seen 함수로 따로 한다.
project_path_gateway__domain_classify_line() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	'' | '#'*)
		printf 'ignore\n'
		return 0
		;;
	*=*) ;;
	*)
		printf 'no_separator\n'
		return 0
		;;
	esac
	if ! project_path_gateway__domain_is_valid_key "${1%%=*}"; then
		printf 'invalid_key\n'
		return 0
	fi
	violation=$(project_path_gateway__domain_path_violation "${1#*=}")
	if [ -n "$violation" ]; then
		printf '%s\n' "$violation"
		return 0
	fi
	printf 'entry\n'
	return 0
)

# 줄의 첫 = 앞(키)을 출력한다. = 가 없으면 빈 출력.
project_path_gateway__domain_line_key() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	*=*) printf '%s' "${1%%=*}" ;;
	esac
	return 0
)

# 줄의 첫 = 뒤 전체(경로)를 출력한다.
project_path_gateway__domain_line_path() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	*=*) printf '%s' "${1#*=}" ;;
	esac
	return 0
)

# 본 키 목록 SEEN(":KEY=줄번호:" 연결)에 KEY를 더한 목록을 출력한다.
project_path_gateway__domain_seen_add() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ -z "$1" ]; then
		printf ':%s=%s:' "$2" "$3"
	else
		printf '%s%s=%s:' "$1" "$2" "$3"
	fi
	return 0
)

# 본 키 목록에서 KEY가 처음 정의된 줄 번호를 출력한다. 없으면 빈 출력.
project_path_gateway__domain_seen_lineno() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $1 in
	*":$2="*)
		rest=${1#*":$2="}
		printf '%s\n' "${rest%%:*}"
		;;
	esac
	return 0
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

# 데이터 파일 절대경로를 출력한다.
project_path_gateway__app_data_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	project_path_gateway__domain_join "$1" .tool/project-path-gateway/project-path-gateway.conf
)

# 데이터 파일을 읽고 검증한다. 유효한 항목마다 "줄번호<TAB>키<TAB>경로" 한 줄을 파일 순서로 출력한다.
# 위반은 끝까지 모두 보고 포트로 보고한다. 반환: 0 유효, 3 규칙 위반, 4 읽기 불가.
project_path_gateway__app_load_entries() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	file=$(project_path_gateway__app_data_file "$1")
	project_path_gateway__port_readable_file "$file" || return 4
	project_path_gateway__port_read_lines "$file" | {
		lineno=0
		bad=0
		seen=
		while IFS= read -r line; do
			lineno=$((lineno + 1))
			code=$(project_path_gateway__domain_classify_line "$line")
			[ "$code" = ignore ] && continue
			key=$(project_path_gateway__domain_line_key "$line")
			first=
			if [ "$code" = entry ]; then
				first=$(project_path_gateway__domain_seen_lineno "$seen" "$key")
				if [ -z "$first" ]; then
					seen=$(project_path_gateway__domain_seen_add "$seen" "$key" "$lineno")
					printf '%s\t%s\t%s\n' "$lineno" "$key" "$(project_path_gateway__domain_line_path "$line")"
					continue
				fi
				code=duplicate_key
			fi
			has_cr=0
			if project_path_gateway__domain_has_cr "$line"; then
				has_cr=1
			fi
			project_path_gateway__port_report_violation "$file" "$lineno" "$code" "$key" "$first" "$has_cr"
			bad=1
		done
		[ "$bad" -eq 0 ]
	} || return 3
	return 0
)

# 런타임 초기화 흐름. 성공하면 루트를, 실패하면 문구에 쓸 상세 값을 끝 표지 방식으로 출력한다.
# 반환: 0 성공, 8 디렉터리 아님(상세: START_DIR), 5 경로 확인 실패(상세: START_DIR),
# 6 루트 표식 없음(상세: 물리 시작 디렉터리), 4 데이터 파일 읽기 불가(상세: 데이터 파일 경로), 3 규칙 위반(상세 없음).
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
	if ! root=$(project_path_gateway__port_find_root "$start"); then
		printf '%sx' "$start"
		return 6
	fi
	root=${root%x}
	project_path_gateway__app_load_entries "$root" >/dev/null
	status=$?
	case $status in
	0)
		printf '%sx' "$root"
		return 0
		;;
	4)
		printf '%sx' "$(project_path_gateway__app_data_file "$root")"
		return 4
		;;
	esac
	return 3
)

# 키에 등록된 경로를 루트와 결합해 출력한다. 반환: 0 성공, 3·4 데이터 파일 오류, 7 미등록 키.
project_path_gateway__app_lookup() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	records=$(project_path_gateway__app_load_entries "$1") || return $?
	tab=$(printf '\t')
	printf '%s\n' "$records" | {
		while IFS= read -r record; do
			rest=${record#*"$tab"}
			if [ "${rest%%"$tab"*}" = "$2" ]; then
				project_path_gateway__domain_join "$1" "${rest#*"$tab"}"
				return 0
			fi
		done
		return 7
	}
)

# 모든 항목의 존재(V-1)와 루트 내부 여부(V-2)를 파일 순서대로 판정한다. 실패 항목은 보고 포트로 보고하고,
# 끝에 "ok <통과 수>" 또는 "fail <실패 수>" 한 줄을 출력한다. 반환: 0 모두 통과, 1 실패 있음, 3·4 데이터 파일 오류.
project_path_gateway__app_verify() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	records=$(project_path_gateway__app_load_entries "$1") || return $?
	tab=$(printf '\t')
	printf '%s\n' "$records" | {
		passed=0
		failed=0
		while IFS= read -r record; do
			[ -n "$record" ] || continue
			rest=${record#*"$tab"}
			key=${rest%%"$tab"*}
			path=${rest#*"$tab"}
			full=$(project_path_gateway__domain_join "$1" "$path")
			if project_path_gateway__port_exists "$full" &&
				physical=$(project_path_gateway__port_resolve_physical "$full"); then
				physical=${physical%x}
				if project_path_gateway__domain_is_inside "$1" "$physical"; then
					passed=$((passed + 1))
				else
					project_path_gateway__port_report_outside "$key" "$path" "$physical"
					failed=$((failed + 1))
				fi
			else
				project_path_gateway__port_report_missing "$key" "$path"
				failed=$((failed + 1))
			fi
		done
		if [ "$failed" -gt 0 ]; then
			printf 'fail %s\n' "$failed"
			return 1
		fi
		printf 'ok %s\n' "$passed"
		return 0
	}
)

# === 계층: 인프라 ===

# 디렉터리이면 반환 0.
project_path_gateway__port_is_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -d "$1" ]
)

# 디렉터리의 물리 경로를 끝 표지 방식으로 출력한다. 실패하면 반환 1.
project_path_gateway__port_physical_dir() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	dir=$(cd -P -- "$1" 2>/dev/null && pwd -P && printf x) || return 1
	dir=${dir%x}
	printf '%sx' "${dir%?}"
	return 0
)

# 일반 파일이고 읽을 수 있으면 반환 0.
project_path_gateway__port_readable_file() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	[ -f "$1" ] && [ -r "$1" ]
)

# 파일의 각 줄을 개행을 붙여 출력한다. 마지막 줄에 개행이 없어도 출력한다.
project_path_gateway__port_read_lines() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	while IFS= read -r line || [ -n "$line" ]; do
		printf '%s\n' "$line"
	done <"$1"
)

# 물리 시작 디렉터리부터 /까지 올라가며 루트 표식 파일이 일반 파일로 있는 가장 가까운 디렉터리를
# 끝 표지 방식으로 출력한다. 찾지 못하면 반환 1 (FR-002 4단계, research R-06).
project_path_gateway__port_find_root() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	dir=$1
	while :; do
		if [ -f "${dir%/}/.tool/project-path-gateway/.project-path-gateway" ]; then
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
	[ -e "$1" ]
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
		if [ -d "$current" ]; then
			project_path_gateway__port_physical_dir "$current"
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
		parent=$(project_path_gateway__port_physical_dir "$parent") || return 1
		parent=${parent%x}
		current=${parent%/}/$name
		if [ ! -L "$current" ]; then
			printf '%sx' "$current"
			return 0
		fi
		count=$((count + 1))
		[ "$count" -le 40 ] || return 1
		target=$(readlink -- "$current" && printf x) || return 1
		target=${target%x}
		target=${target%?}
		case $target in
		/*) current=$target ;;
		*) current=${parent%/}/$target ;;
		esac
	done
)

# === 계층: 인터페이스 ===

# 공통 오류 출력: project-path-gateway: FUNC: MESSAGE
project_path_gateway__if_error() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf 'project-path-gateway: %s: %s\n' "$1" "$2" >&2
)

# 데이터 파일 위반 보고 포트 구현 (contracts/library-api.md 6절).
project_path_gateway__port_report_violation() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $3 in
	no_separator) message='KEY=경로 형식이 아닙니다' ;;
	invalid_key) message="키 형식이 잘못되었습니다(대문자로 시작, 대문자·숫자·_만 허용): $4" ;;
	empty_path) message="경로가 비어 있습니다: $4" ;;
	absolute_path) message="경로는 /로 시작할 수 없습니다: $4" ;;
	parent_segment) message="경로에 .. 세그먼트를 쓸 수 없습니다: $4" ;;
	carriage_return) message='CR 문자가 포함되어 있습니다(CRLF 줄 끝인지 확인하세요)' ;;
	duplicate_key) message="중복된 키입니다($5번째 줄에서 정의됨): $4" ;;
	*) message="알 수 없는 위반입니다: $3" ;;
	esac
	if [ "$6" = 1 ] && [ "$3" != carriage_return ]; then
		message="$message (CRLF 줄 끝인지 확인하세요)"
	fi
	printf 'project-path-gateway: %s:%s: %s\n' "$1" "$2" "$message" >&2
)

# 초기화 실패 문구를 출력한다. $1: 내부 코드, $2: 끝 표지가 붙은 상세 값.
project_path_gateway__if_init_fail() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	detail=${2%x}
	case $1 in
	8) project_path_gateway__if_error project_path_gateway_init "디렉터리가 아닙니다: $detail" ;;
	5) project_path_gateway__if_error project_path_gateway_init "경로를 확인할 수 없습니다: $detail" ;;
	6) project_path_gateway__if_error project_path_gateway_init "루트 표식 파일(.tool/project-path-gateway/.project-path-gateway)을 찾지 못했습니다: ${detail}부터 /까지" ;;
	4) project_path_gateway__if_error project_path_gateway_init "데이터 파일을 읽을 수 없습니다: $detail" ;;
	3) ;;
	*) project_path_gateway__if_error project_path_gateway_init "알 수 없는 오류입니다(코드 $1)" ;;
	esac
	return 0
)

# 데이터 파일 오류 문구를 출력한다. $1: 공개 함수 이름, $2: 내부 코드, $3: 루트.
project_path_gateway__if_data_file_fail() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$2" = 4 ]; then
		project_path_gateway__if_error "$1" "데이터 파일을 읽을 수 없습니다: $(project_path_gateway__app_data_file "$3")"
	fi
	return 0
)

# 공개 함수: 런타임 초기화 (contracts/library-api.md 3절).
# 호출 셸 변수 PROJECT_PATH_GATEWAY_ROOT를 설정·해제해야 하므로 서브셸 본문을 쓰지 않는다.
# 본문에서는 다른 변수를 만들지 않고, 명령 치환 대입은 if 조건 안에서만 수행한다.
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
		project_path_gateway__if_init_fail "$?" "${PROJECT_PATH_GATEWAY_ROOT-}"
		unset PROJECT_PATH_GATEWAY_ROOT
		return 2
	fi
}

# 공개 함수: 키로 절대경로 조회 (contracts/library-api.md 4절).
project_path_gateway_get() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$#" -ne 1 ]; then
		project_path_gateway__if_error project_path_gateway_get '인자는 KEY 1개여야 합니다'
		return 2
	fi
	if [ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ]; then
		project_path_gateway__if_error project_path_gateway_get '초기화되지 않았습니다. project_path_gateway_init을 먼저 호출하세요'
		return 2
	fi
	result=$(project_path_gateway__app_lookup "$PROJECT_PATH_GATEWAY_ROOT" "$1")
	status=$?
	case $status in
	0)
		printf '%s\n' "$result"
		return 0
		;;
	7) project_path_gateway__if_error project_path_gateway_get "등록되지 않은 키입니다: $1" ;;
	*) project_path_gateway__if_data_file_fail project_path_gateway_get "$status" "$PROJECT_PATH_GATEWAY_ROOT" ;;
	esac
	return 2
)

# 검증 누락 보고 포트 구현.
project_path_gateway__port_report_missing() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf 'project-path-gateway: 누락: %s=%s\n' "$1" "$2" >&2
)

# 검증 루트 밖 보고 포트 구현.
project_path_gateway__port_report_outside() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf 'project-path-gateway: 루트 밖: %s=%s -> %s\n' "$1" "$2" "$3" >&2
)

# 공개 함수: 등록 경로 검증 (contracts/library-api.md 5절).
project_path_gateway_verify() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$#" -ne 0 ]; then
		project_path_gateway__if_error project_path_gateway_verify '인자를 받지 않습니다'
		return 2
	fi
	if [ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ]; then
		project_path_gateway__if_error project_path_gateway_verify '초기화되지 않았습니다. project_path_gateway_init을 먼저 호출하세요'
		return 2
	fi
	result=$(project_path_gateway__app_verify "$PROJECT_PATH_GATEWAY_ROOT")
	status=$?
	case $status in
	0)
		printf 'project-path-gateway: 검증 통과 %s건\n' "${result#ok }"
		return 0
		;;
	1)
		printf 'project-path-gateway: 검증 실패 %s건\n' "${result#fail }" >&2
		return 1
		;;
	esac
	project_path_gateway__if_data_file_fail project_path_gateway_verify "$status" "$PROJECT_PATH_GATEWAY_ROOT"
	return 2
)
