#!/bin/sh
# project-path-gateway 제거 스크립트 (contracts/install.md 2절)
#
# 사용법: sh uninstall.sh [--prefix DIR]
#
# 설치 목록(install-manifest)에 적힌 파일만 지운다. 프로젝트 안 .tools/project-path-gateway/는 건드리지 않는다.
#
# 구조: 도메인 → 애플리케이션 → 인프라 → 인터페이스 네 구획으로 나눈다.
# 도메인은 모델별 소제목(# --- 모델: ... ---)으로 나누고, 애플리케이션 구획 머리에 포트 목록(# 입력 포트:, # 출력 포트:)을 둔다.
# 이름 규칙: 인프라는 ppg__port_*(입력 포트)·ppg__infra_*(도우미)·ppg__sys_*(시스템 포트), 인터페이스는
# ppg__out_*(출력 포트 구현)·ppg__if_*(검사·결과 매핑). 출력 문구와 반환값은 인터페이스에서만 정한다(scripts/lint.sh 5절).
# 파일 시스템 접근은 인프라 구획의 시스템 포트(ppg__sys_*)에서만 한다.

# === 계층: 도메인 ===

# --- 모델: 설치 배치 (기능 005 research R-05) ---

# 공유 디렉터리(PREFIX 기준).
ppg__domain_layout_share_dir() {
	printf 'share/project-path-gateway\n'
}

# 설치 목록(PREFIX 기준).
ppg__domain_layout_manifest() {
	printf 'share/project-path-gateway/install-manifest\n'
}

# --- 모델: 설치 목록 ---

# 설치 목록 항목 위반 원인을 출력한다: absolute(절대경로), parent(.. 세그먼트). 위반이 없으면 빈 출력.
ppg__domain_manifest_violation() {
	case $1 in
	/*)
		printf 'absolute\n'
		return 0
		;;
	esac
	case /$1/ in
	*/../*) printf 'parent\n' ;;
	esac
	return 0
}

# LF로 이은 목록의 첫 줄을 출력한다.
ppg__domain_list_first() {
	ppg_domain_nl='
'
	printf '%s\n' "${1%%"$ppg_domain_nl"*}"
}

# LF로 이은 목록에서 첫 줄을 뺀 나머지를 출력한다. 마지막 줄이면 빈 출력.
ppg__domain_list_rest() {
	ppg_domain_nl='
'
	case $1 in
	*"$ppg_domain_nl"*) printf '%s\n' "${1#*"$ppg_domain_nl"}" ;;
	esac
}

# === 계층: 애플리케이션 ===

# 입력 포트: ppg__port_manifest_exists ppg__port_read_manifest ppg__port_remove ppg__port_remove_dir
# 출력 포트: ppg__out_no_manifest ppg__out_unsafe ppg__out_done

# 제거 흐름. 반환: 0 성공, 1 설치 기록 없음·안전하지 않은 목록·목록 읽기 실패.
# 지우기 전에 목록 전체를 검사한다. 위반 항목이 하나라도 있으면 아무것도 지우지 않는다.
ppg__app_uninstall() {
	ppg_app_prefix=$1
	ppg_app_share=$ppg_app_prefix/$(ppg__domain_layout_share_dir)
	ppg_app_manifest=$ppg_app_prefix/$(ppg__domain_layout_manifest)
	if ! ppg__port_manifest_exists "$ppg_app_manifest"; then
		ppg__out_no_manifest "$ppg_app_prefix"
		return 1
	fi
	ppg_app_entries=$(ppg__port_read_manifest "$ppg_app_manifest") || return 1
	ppg_app_rest=$ppg_app_entries
	while [ -n "$ppg_app_rest" ]; do
		ppg_app_entry=$(ppg__domain_list_first "$ppg_app_rest")
		ppg_app_rest=$(ppg__domain_list_rest "$ppg_app_rest")
		ppg_app_violation=$(ppg__domain_manifest_violation "$ppg_app_entry")
		if [ -n "$ppg_app_violation" ]; then
			ppg__out_unsafe "$ppg_app_violation" "$ppg_app_entry"
			return 1
		fi
	done
	ppg_app_rest=$ppg_app_entries
	while [ -n "$ppg_app_rest" ]; do
		ppg_app_entry=$(ppg__domain_list_first "$ppg_app_rest")
		ppg_app_rest=$(ppg__domain_list_rest "$ppg_app_rest")
		[ -n "$ppg_app_entry" ] || continue
		ppg__port_remove "$ppg_app_prefix/$ppg_app_entry"
	done
	ppg__port_remove_dir "$ppg_app_share"
	ppg__out_done "$ppg_app_prefix"
	return 0
}

# === 계층: 인프라 ===

ppg__port_manifest_exists() {
	ppg__sys_is_file "$1"
}

# 설치 목록의 줄을 한 줄씩 출력한다. 마지막 줄에 개행이 없어도 출력한다.
ppg__port_read_manifest() {
	ppg__sys_read_lines "$1"
}

ppg__port_remove() {
	ppg__sys_remove "$1"
}

ppg__port_remove_dir() {
	ppg__sys_rmdir "$1"
	return 0
}

# 시스템 포트: 일반 파일이면 반환 0 (링크를 따라간다).
ppg__sys_is_file() {
	[ -f "$1" ]
}

# 시스템 포트: 파일의 각 줄을 개행을 붙여 출력한다. 마지막 줄에 개행이 없어도 출력한다.
ppg__sys_read_lines() {
	while IFS= read -r ppg_sys_line || [ -n "$ppg_sys_line" ]; do
		printf '%s\n' "$ppg_sys_line"
	done <"$1"
}

# 시스템 포트: 파일을 지운다. 없어도 성공이다.
ppg__sys_remove() {
	rm -f -- "$1" 2>/dev/null
}

# 시스템 포트: 빈 디렉터리를 지운다.
ppg__sys_rmdir() {
	rmdir -- "$1" 2>/dev/null
}

# === 계층: 인터페이스 ===

ppg__if_usage() {
	printf '사용법: sh uninstall.sh [--prefix DIR]\n' >&2
}

# 출력 포트 구현: 설치 기록 없음.
ppg__out_no_manifest() {
	printf 'project-path-gateway: 설치 기록이 없습니다: %s\n' "$1" >&2
}

# 출력 포트 구현: 안전하지 않은 설치 목록. $1: absolute 또는 parent, $2: 항목.
ppg__out_unsafe() {
	case $1 in
	absolute) printf 'project-path-gateway: 설치 목록에 절대경로가 있어 제거하지 않습니다: %s\n' "$2" >&2 ;;
	*) printf 'project-path-gateway: 설치 목록에 .. 세그먼트가 있어 제거하지 않습니다: %s\n' "$2" >&2 ;;
	esac
}

# 출력 포트 구현: 제거 완료.
ppg__out_done() {
	printf 'project-path-gateway: 제거 완료: %s\n' "$1"
}

# 제거 결과 매핑: 애플리케이션 결과 코드를 종료 코드로 바꾼다 (0 → 0, 그 밖 → 1).
ppg__if_uninstall_result() {
	case $1 in
	0) return 0 ;;
	*) return 1 ;;
	esac
}

main() {
	ppg_if_prefix=${PREFIX-}
	while [ "$#" -gt 0 ]; do
		case $1 in
		--prefix)
			if [ "$#" -lt 2 ] || [ -z "$2" ]; then
				ppg__if_usage
				exit 2
			fi
			ppg_if_prefix=$2
			shift 2
			;;
		*)
			ppg__if_usage
			exit 2
			;;
		esac
	done
	[ -n "$ppg_if_prefix" ] || ppg_if_prefix=$HOME/.local
	ppg__app_uninstall "$ppg_if_prefix"
	ppg__if_uninstall_result "$?"
	exit "$?"
}

[ "${PPG_SOURCE_ONLY-}" = 1 ] || main "$@"
