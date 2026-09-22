# project-path-gateway 1.0.0
#
# 프로젝트 경로 게이트웨이 라이브러리.
# 호출 셸에서 이 파일을 불러온(source) 뒤 공개 함수 다섯 개를 사용한다.
#
#   project_path_gateway_init [START_DIR]         루트 표식 파일을 찾아 루트를 한 번 계산한다
#   project_path_gateway_get KEY                  키에 등록된 경로를 루트 기준 절대경로로 출력한다
#   project_path_gateway_verify [REPORT_FILE]     등록된 모든 경로의 존재와 루트 내부 여부를 확인한다
#   project_path_gateway_add KEY PATH             새 키와 경로를 데이터 파일 끝에 등록한다(키가 있으면 오류)
#   project_path_gateway_update KEY PATH          등록된 키의 경로를 바꾼다(키가 없으면 오류)
#
# 반환값: 0 성공, 1 검증 실패, 2 인자 오류·미초기화·루트 오류·데이터 파일 오류·미등록 키·이미 등록된 키·파일 쓰기 실패.
#
# 구조: 도메인 → 애플리케이션 → 인프라 → 인터페이스 네 구획으로 나눈다.
# project_path_gateway_init 외의 모든 함수는 서브셸 본문으로 정의해 호출 셸 상태를 바꾸지 않고,
# 본문 첫 줄에서 셸 옵션, IFS, CDPATH를 기본 상태로 되돌린다.
# 파일 시스템 접근은 인프라 구획의 시스템 포트(project_path_gateway__sys_*)에서만 한다.
# 경로를 명령 치환으로 전달하는 함수는 끝 개행이 사라지지 않도록 값 뒤에 표지 문자 x를 붙인다.
# 내부 결과 코드: 3 데이터 파일 규칙 위반, 4 데이터 파일 읽기 불가, 5 경로 확인 실패,
# 6 루트 표식 파일 없음, 7 미등록 키, 8 디렉터리가 아님, 9 등록·갱신 인자 규칙 위반, 10 이미 등록된 키,
# 11 데이터 파일이 링크, 12 데이터 파일 쓰기 권한 없음, 13 데이터 파일 교체 실패.

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

# 경로 규칙 위반 원인 코드를 출력한다. 위반이 없으면 아무것도 출력하지 않는다.
# 순서: empty_path, absolute_path, parent_segment, carriage_return, line_feed. 경로 규칙을 판정하는 곳은 이 함수뿐이다 (기능 005 FR-003).
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
	case $1 in
	*"$cr"*) printf 'carriage_return\n' ;;
	*"$nl"*) printf 'line_feed\n' ;;
	esac
	return 0
)

# --- 모델: 항목 ---
# 항목 레코드 표현 "줄번호<TAB>키<TAB>경로"는 이 소구획의 함수만 안다 (기능 005 FR-006, research R-01).

# 항목 레코드를 만들어 출력한다(끝 LF 포함).
project_path_gateway__domain_entry_new() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	printf '%s\t%s\t%s\n' "$1" "$2" "$3"
	return 0
)

# 등록·갱신 인자 KEY·PATH의 첫 위반 코드를 출력한다. 위반이 없으면 아무것도 출력하지 않는다 (기능 004 research R-02).
# 순서: 키 모델, 경로 모델.
project_path_gateway__domain_entry_violation() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if ! project_path_gateway__domain_key_is_valid "$1"; then
		printf 'invalid_key\n'
		return 0
	fi
	project_path_gateway__domain_path_violation "$2"
)

# 데이터 파일 한 줄을 해석한다 (기능 005 data-model 1.4). $1: 줄 번호, $2: 줄.
# 반환 0: 유효 항목(레코드 출력), 1: 규칙 위반(원인 코드 출력), 2: 빈 줄·주석(출력 없음).
# 중복 키 검사는 파일 전체 상태가 필요하므로 seen_register로 따로 한다.
project_path_gateway__domain_entry_parse_line() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	case $2 in
	'' | '#'*) return 2 ;;
	*=*) ;;
	*)
		printf 'no_separator\n'
		return 1
		;;
	esac
	key=${2%%=*}
	path=${2#*=}
	if ! project_path_gateway__domain_key_is_valid "$key"; then
		printf 'invalid_key\n'
		return 1
	fi
	violation=$(project_path_gateway__domain_path_violation "$path")
	if [ -n "$violation" ]; then
		printf '%s\n' "$violation"
		return 1
	fi
	# entry_new와 같은 표현. 줄마다 호출 한 번을 줄이려고 여기서 바로 만든다 (기능 005 research R-06).
	printf '%s\t%s\t%s\n' "$1" "$key" "$path"
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

# --- 모델: 항목 목록 ---

# 본 키 목록 SEEN(":KEY=줄번호:" 연결)에 레코드의 키를 등록한다.
# 처음 본 키이면 새 목록을 출력하고 반환 0, 이미 본 키이면 처음 정의된 줄 번호를 출력하고 반환 1.
project_path_gateway__domain_seen_register() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	tab='	'
	lineno=${2%%"$tab"*}
	rest=${2#*"$tab"}
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

# --- 이전 함수 (기능 005 T017에서 제거) ---

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

# 등록 새 원문을 끝 표지 방식으로 출력한다 (기능 004 research R-05). 원문 끝에 KEY=PATH와 LF를 더하며,
# 원문이 LF 없이 끝나면 LF를 먼저 더한다.
project_path_gateway__domain_append_entry() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	nl='
'
	case $1 in
	'' | *"$nl") printf '%s%s=%s\nx' "$1" "$2" "$3" ;;
	*) printf '%s\n%s=%s\nx' "$1" "$2" "$3" ;;
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
	project_path_gateway__domain_join "$1" .tools/project-path-gateway/project-path-gateway.conf
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

# 등록(add)·갱신(update) 흐름 (기능 004 research R-01). 인자 규칙 위반이면 위반 코드를 출력한다.
# 반환: 0 성공, 9 인자 규칙 위반, 3·4 데이터 파일 오류, 10 이미 등록된 키, 7 미등록 키,
# 11 데이터 파일이 링크, 12 쓰기 권한 없음, 13 교체 실패.
project_path_gateway__app_edit() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	violation=$(project_path_gateway__domain_entry_violation "$3" "$4")
	if [ -n "$violation" ]; then
		printf '%s\n' "$violation"
		return 9
	fi
	records=$(project_path_gateway__app_load_entries "$2") || return $?
	tab=$(printf '\t')
	match=$(printf '%s\n' "$records" | {
		while IFS= read -r record; do
			rest=${record#*"$tab"}
			if [ "${rest%%"$tab"*}" = "$3" ]; then
				printf '%sx' "$record"
				break
			fi
		done
	})
	match=${match%x}
	file=$(project_path_gateway__app_data_file "$2")
	case $1 in
	add)
		[ -z "$match" ] || return 10
		content=$(project_path_gateway__port_read_file "$file") || return 4
		content=$(project_path_gateway__domain_append_entry "${content%x}" "$3" "$4")
		;;
	update)
		[ -n "$match" ] || return 7
		rest=${match#*"$tab"}
		[ "${rest#*"$tab"}" = "$4" ] && return 0
		content=$(project_path_gateway__port_read_file "$file") || return 4
		content=$(project_path_gateway__domain_replace_line "${content%x}" "${match%%"$tab"*}" "$3=$4") || return 13
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
# 끝 표지 방식으로 출력한다. 찾지 못하면 반환 1 (FR-002 4단계, research R-06).
project_path_gateway__port_find_root() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	dir=$1
	while :; do
		if project_path_gateway__sys_is_file "${dir%/}/.tools/project-path-gateway/.project-path-gateway"; then
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
	6) project_path_gateway__if_error project_path_gateway_init "루트 표식 파일(.tools/project-path-gateway/.project-path-gateway)을 찾지 못했습니다: ${detail}부터 /까지" ;;
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

# 리포트를 지정한 검증 (기능 003 research R-02). 항목 줄과 요약 코드를 한 번에 받아 기존과 같은 문구로 출력하고
# 같은 줄을 리포트로 저장한다. $1: 루트, $2: 리포트 파일. 반환: 0 통과, 1 검증 실패, 2 오류.
project_path_gateway__if_verify_report() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	nl='
'
	captured=$(project_path_gateway__app_verify "$1" 2>&1
		printf 'x%s' "$?")
	status=${captured##*x}
	captured=${captured%x*}
	case $status in
	0)
		body="project-path-gateway: 검증 통과 ${captured#ok }"
		body="${body%"$nl"}건$nl"
		printf '%s' "$body"
		if ! project_path_gateway__app_write_report "$2" "$body"; then
			project_path_gateway__if_error project_path_gateway_verify "리포트 파일을 쓸 수 없습니다: $2"
			return 2
		fi
		return 0
		;;
	1) ;;
	*)
		printf '%s' "$captured" >&2
		project_path_gateway__if_data_file_fail project_path_gateway_verify "$status" "$1"
		return 2
		;;
	esac
	last=${captured%"$nl"}
	summary=${last##*"$nl"}
	body="${last%"$summary"}project-path-gateway: 검증 실패 ${summary#fail }건$nl"
	printf '%s' "$body" >&2
	if ! project_path_gateway__app_write_report "$2" "$body"; then
		project_path_gateway__if_error project_path_gateway_verify "리포트 파일을 쓸 수 없습니다: $2"
		return 2
	fi
	return 1
)

# 공개 함수: 등록 경로 검증 (contracts/library-api.md 5절, 기능 003 REPORT_FILE 선택 인자).
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
	if [ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ]; then
		project_path_gateway__if_error project_path_gateway_verify '초기화되지 않았습니다. project_path_gateway_init을 먼저 호출하세요'
		return 2
	fi
	if [ "$#" -eq 1 ]; then
		project_path_gateway__if_verify_report "$PROJECT_PATH_GATEWAY_ROOT" "$1"
		return $?
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

# 등록·갱신 실패 문구를 출력한다 (기능 004 contracts/library-api-add-update.md 2절).
# $1: 공개 함수 이름, $2: 내부 코드, $3: 상세(위반 코드), $4: 루트, $5: KEY, $6: PATH.
project_path_gateway__if_edit_fail() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	file=$(project_path_gateway__app_data_file "$4")
	case $2 in
	9)
		case $3 in
		invalid_key) message="키 형식이 잘못되었습니다(대문자로 시작, 대문자·숫자·_만 허용): $5" ;;
		empty_path) message='경로가 비어 있습니다' ;;
		absolute_path) message="경로는 /로 시작할 수 없습니다: $6" ;;
		parent_segment) message="경로에 .. 세그먼트를 쓸 수 없습니다: $6" ;;
		carriage_return) message='경로에 CR 문자를 쓸 수 없습니다' ;;
		line_feed) message='경로에 LF 문자를 쓸 수 없습니다' ;;
		*) message="알 수 없는 위반입니다: $3" ;;
		esac
		;;
	3) return 0 ;;
	4) message="데이터 파일을 읽을 수 없습니다: $file" ;;
	7) message="등록되지 않은 키입니다: $5" ;;
	10) message="이미 등록된 키입니다: $5" ;;
	11) message="데이터 파일이 심볼릭 링크라 바꿀 수 없습니다: $file" ;;
	12) message="데이터 파일에 쓰기 권한이 없습니다: $file" ;;
	13) message="데이터 파일을 쓸 수 없습니다: $file" ;;
	*) message="알 수 없는 오류입니다(코드 $2)" ;;
	esac
	project_path_gateway__if_error "$1" "$message"
	return 0
)

# 공개 함수: 새 경로 항목 등록 (기능 004). 키가 이미 있으면 반환 2.
project_path_gateway_add() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$#" -ne 2 ]; then
		project_path_gateway__if_error project_path_gateway_add '인자는 KEY와 PATH 2개여야 합니다'
		return 2
	fi
	if [ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ]; then
		project_path_gateway__if_error project_path_gateway_add '초기화되지 않았습니다. project_path_gateway_init을 먼저 호출하세요'
		return 2
	fi
	detail=$(project_path_gateway__app_edit add "$PROJECT_PATH_GATEWAY_ROOT" "$1" "$2")
	status=$?
	[ "$status" -eq 0 ] && return 0
	project_path_gateway__if_edit_fail project_path_gateway_add "$status" "$detail" "$PROJECT_PATH_GATEWAY_ROOT" "$1" "$2"
	return 2
)

# 공개 함수: 등록된 키의 경로 갱신 (기능 004). 키가 없으면 반환 2.
project_path_gateway_update() (
	set +e +u +f
	IFS=' 	''
'
	unset CDPATH
	if [ "$#" -ne 2 ]; then
		project_path_gateway__if_error project_path_gateway_update '인자는 KEY와 PATH 2개여야 합니다'
		return 2
	fi
	if [ -z "${PROJECT_PATH_GATEWAY_ROOT+x}" ]; then
		project_path_gateway__if_error project_path_gateway_update '초기화되지 않았습니다. project_path_gateway_init을 먼저 호출하세요'
		return 2
	fi
	detail=$(project_path_gateway__app_edit update "$PROJECT_PATH_GATEWAY_ROOT" "$1" "$2")
	status=$?
	[ "$status" -eq 0 ] && return 0
	project_path_gateway__if_edit_fail project_path_gateway_update "$status" "$detail" "$PROJECT_PATH_GATEWAY_ROOT" "$1" "$2"
	return 2
)
