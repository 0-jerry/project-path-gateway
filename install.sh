#!/bin/sh
# project-path-gateway 설치 스크립트 (contracts/install.md 1절)
#
# 사용법: sh install.sh [--prefix DIR]
#
# 설치 위치 우선순위: --prefix > 환경 변수 PREFIX > $HOME/.local
# 이 스크립트가 있는 저장소를 원본으로 쓰며, 관리자 권한을 요구하지 않는다.
#
# 구조: 도메인 → 애플리케이션 → 인프라 → 인터페이스 네 구획으로 나눈다.
# 도메인은 모델별 소제목(# --- 모델: ... ---)으로 나누고, 애플리케이션 구획 머리에 포트 목록(# 입력 포트:, # 출력 포트:)을 둔다.
# 이름 규칙: 인프라는 ppg__port_*(입력 포트)·ppg__infra_*(도우미)·ppg__sys_*(시스템 포트), 인터페이스는
# ppg__out_*(출력 포트 구현)·ppg__if_*(검사·결과 매핑). 출력 문구와 반환값은 인터페이스에서만 정한다(scripts/lint.sh 5절).
# 파일 시스템·프로세스 환경 접근은 인프라 구획의 시스템 포트(ppg__sys_*)에서만 한다.

# === 계층: 도메인 ===

# --- 모델: 설치 배치 (기능 005 research R-05) ---

# 설치하는 파일 종류와 순서. 설치 목록(manifest)은 마지막에 따로 설치한다.
ppg__domain_layout_kinds() {
	printf 'bin library version\n'
}

# 종류별 원본 경로(저장소 기준).
ppg__domain_layout_source() {
	case $1 in
	bin) printf 'bin/project-path-gateway\n' ;;
	library) printf 'lib/project-path-gateway.sh\n' ;;
	version) printf 'VERSION\n' ;;
	esac
}

# 종류별 설치 경로(PREFIX 기준).
ppg__domain_layout_installed() {
	case $1 in
	bin) printf 'bin/project-path-gateway\n' ;;
	library) printf 'share/project-path-gateway/project-path-gateway.sh\n' ;;
	version) printf 'share/project-path-gateway/VERSION\n' ;;
	manifest) printf 'share/project-path-gateway/install-manifest\n' ;;
	esac
}

# 종류별 파일 권한.
ppg__domain_layout_mode() {
	case $1 in
	bin) printf '755\n' ;;
	*) printf '644\n' ;;
	esac
}

# 설치가 만드는 디렉터리(PREFIX 기준).
ppg__domain_layout_dirs() {
	printf 'bin share/project-path-gateway\n'
}

# 공유 디렉터리(PREFIX 기준).
ppg__domain_layout_share_dir() {
	printf 'share/project-path-gateway\n'
}

# 설치 목록 내용: PREFIX 기준 상대경로, 이 목록 파일 포함.
ppg__domain_manifest_content() {
	for ppg_domain_kind in $(ppg__domain_layout_kinds) manifest; do
		ppg__domain_layout_installed "$ppg_domain_kind"
	done
}

# === 계층: 애플리케이션 ===

# 입력 포트: ppg__port_source_dir ppg__port_read_version ppg__port_make_dir ppg__port_install_file
# 입력 포트: ppg__port_manifest_temp ppg__port_write_manifest ppg__port_remove
# 출력 포트: ppg__out_failure ppg__out_done

# 설치 흐름. 실패하면 실패 경로를 출력 포트로 보고하고 반환 1, 성공하면 완료를 보고하고 반환 0.
ppg__app_install() {
	ppg_app_prefix=$1
	if ! ppg_app_source=$(ppg__port_source_dir); then
		ppg__out_failure "${ppg_app_source%x}"
		return 1
	fi
	ppg_app_source=${ppg_app_source%x}
	ppg_app_version_file=$ppg_app_source/$(ppg__domain_layout_source version)
	if ! ppg_app_version=$(ppg__port_read_version "$ppg_app_version_file"); then
		ppg__out_failure "$ppg_app_version_file"
		return 1
	fi
	ppg_app_version=${ppg_app_version%x}

	for ppg_app_dir in $(ppg__domain_layout_dirs); do
		if ! ppg__port_make_dir "$ppg_app_prefix/$ppg_app_dir"; then
			ppg__out_failure "$ppg_app_prefix/$ppg_app_dir"
			return 1
		fi
	done

	for ppg_app_kind in $(ppg__domain_layout_kinds); do
		ppg__app_install_one "$ppg_app_source/$(ppg__domain_layout_source "$ppg_app_kind")" \
			"$ppg_app_prefix/$(ppg__domain_layout_installed "$ppg_app_kind")" "$(ppg__domain_layout_mode "$ppg_app_kind")" || return 1
	done

	ppg_app_manifest=$ppg_app_prefix/$(ppg__domain_layout_installed manifest)
	ppg_app_manifest_temp=$(ppg__port_manifest_temp "$ppg_app_prefix/$(ppg__domain_layout_share_dir)")
	if ! ppg__port_write_manifest "$ppg_app_manifest_temp"; then
		ppg__port_remove "$ppg_app_manifest_temp"
		ppg__out_failure "$ppg_app_manifest"
		return 1
	fi
	ppg__app_install_one "$ppg_app_manifest_temp" "$ppg_app_manifest" "$(ppg__domain_layout_mode manifest)" || return 1
	ppg__port_remove "$ppg_app_manifest_temp"

	ppg__out_done "$ppg_app_prefix" "$ppg_app_version"
	return 0
}

# 파일 하나를 설치한다. 실패하면 대상 경로를 보고하고 반환 1.
ppg__app_install_one() {
	if ppg__port_install_file "$1" "$2" "$3"; then
		return 0
	fi
	ppg__out_failure "$2"
	return 1
}

# === 계층: 인프라 ===

# 이 스크립트가 있는 디렉터리의 물리 경로를 끝 표지 방식으로 출력한다. 실패하면 스크립트 디렉터리를 출력하고 반환 1.
ppg__port_source_dir() {
	ppg_infra_self=$(ppg__sys_self_path)
	ppg_infra_self=${ppg_infra_self%x}
	case $ppg_infra_self in
	*/*) ppg_infra_script_dir=${ppg_infra_self%/*} ;;
	*) ppg_infra_script_dir=. ;;
	esac
	ppg__sys_physical_dir "$ppg_infra_script_dir" && return 0
	printf '%sx' "$ppg_infra_script_dir"
	return 1
}

# VERSION 파일 내용에서 끝 개행을 뺀 값을 끝 표지 방식으로 출력한다.
ppg__port_read_version() {
	ppg_infra_version=$(ppg__sys_read_file "$1") || return 1
	ppg_infra_version=${ppg_infra_version%x}
	ppg_infra_nl='
'
	while :; do
		case $ppg_infra_version in
		*"$ppg_infra_nl") ppg_infra_version=${ppg_infra_version%?} ;;
		*) break ;;
		esac
	done
	printf '%sx' "$ppg_infra_version"
}

ppg__port_make_dir() {
	ppg__sys_mkdir_p "$1"
}

# 원본을 같은 디렉터리의 임시 파일 <대상>.ppg-install.<PID>에 복사하고 권한을 정한 뒤 mv -f로 교체한다.
ppg__port_install_file() {
	ppg_infra_pid=$(ppg__sys_pid)
	ppg_infra_temp=$2.ppg-install.$ppg_infra_pid
	if ppg__sys_copy_to "$1" "$ppg_infra_temp" &&
		ppg__sys_chmod "$3" "$ppg_infra_temp" &&
		ppg__sys_move "$ppg_infra_temp" "$2"; then
		return 0
	fi
	ppg__sys_remove "$ppg_infra_temp"
	return 1
}

# 설치 목록 임시 파일 경로: <공유 디렉터리>/install-manifest.ppg-manifest.<PID>
ppg__port_manifest_temp() {
	ppg_infra_pid=$(ppg__sys_pid)
	printf '%s/install-manifest.ppg-manifest.%s\n' "$1" "$ppg_infra_pid"
}

ppg__port_write_manifest() {
	ppg_infra_content=$(ppg__domain_manifest_content && printf x)
	ppg__sys_write_text "$1" "${ppg_infra_content%x}"
}

ppg__port_remove() {
	ppg__sys_remove "$1"
}

# 시스템 포트: 실행 파일 이름($0)을 끝 표지 방식으로 출력한다.
ppg__sys_self_path() {
	printf '%sx' "$0"
}

# 시스템 포트: 디렉터리의 물리 경로를 끝 표지 방식으로 출력한다.
ppg__sys_physical_dir() {
	ppg_sys_dir=$(cd -P -- "$1" 2>/dev/null && pwd -P && printf x) || return 1
	ppg_sys_dir=${ppg_sys_dir%x}
	printf '%sx' "${ppg_sys_dir%?}"
}

# 시스템 포트: 파일 내용을 끝 표지 방식으로 출력한다.
ppg__sys_read_file() {
	ppg_sys_text=$(cat -- "$1" && printf x) || return 1
	printf '%s' "$ppg_sys_text"
}

# 시스템 포트: 현재 셸 PID를 출력한다.
ppg__sys_pid() {
	printf '%s\n' "$$"
}

# 시스템 포트: 디렉터리와 없는 상위 디렉터리를 만든다.
ppg__sys_mkdir_p() {
	mkdir -p -- "$1" 2>/dev/null
}

# 시스템 포트: 원본 파일 내용을 대상 파일에 쓴다.
ppg__sys_copy_to() {
	{ cat -- "$1" >"$2"; } 2>/dev/null
}

# 시스템 포트: 파일 권한을 바꾼다.
ppg__sys_chmod() {
	chmod "$1" "$2"
}

# 시스템 포트: 파일을 옮겨 대상을 교체한다.
ppg__sys_move() {
	mv -f -- "$1" "$2" 2>/dev/null
}

# 시스템 포트: 파일을 지운다. 없어도 성공이다.
ppg__sys_remove() {
	rm -f -- "$1" 2>/dev/null
}

# 시스템 포트: 문자열을 파일에 그대로 쓴다.
ppg__sys_write_text() {
	{ printf '%s' "$2" >"$1"; } 2>/dev/null
}

# === 계층: 인터페이스 ===

ppg__if_usage() {
	printf '사용법: sh install.sh [--prefix DIR]\n' >&2
}

# 출력 포트 구현: 설치 실패 보고.
ppg__out_failure() {
	printf 'project-path-gateway: 설치 실패: %s\n' "$1" >&2
}

# 출력 포트 구현: 설치 완료 보고. PREFIX/bin이 PATH에 없으면 안내를 덧붙인다.
ppg__out_done() {
	printf 'project-path-gateway: 설치 완료: %s (버전 %s)\n' "$1" "$2"
	case ":${PATH-}:" in
	*":$1/bin:"*) ;;
	*)
		printf 'project-path-gateway: %s가 PATH에 없습니다. 셸 설정 파일에 다음 줄을 추가하세요:\n' "$1/bin"
		printf '  export PATH="%s/bin:$PATH"\n' "$1"
		;;
	esac
}

# 설치 결과 매핑: 애플리케이션 결과 코드를 종료 코드로 바꾼다 (0 → 0, 그 밖 → 1).
ppg__if_install_result() {
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
	ppg__app_install "$ppg_if_prefix"
	ppg__if_install_result "$?"
	exit "$?"
}

[ "${PPG_SOURCE_ONLY-}" = 1 ] || main "$@"
