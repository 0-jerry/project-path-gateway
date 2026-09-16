#!/bin/sh
# project-path-gateway 설치 스크립트 (contracts/install.md 1절)
#
# 사용법: sh install.sh [--prefix DIR]
#
# 설치 위치 우선순위: --prefix > 환경 변수 PREFIX > $HOME/.local
# 이 스크립트가 있는 저장소를 원본으로 쓰며, 관리자 권한을 요구하지 않는다.

usage() {
	printf '사용법: sh install.sh [--prefix DIR]\n' >&2
}

fail() {
	printf 'project-path-gateway: 설치 실패: %s\n' "$1" >&2
	exit 1
}

prefix=${PREFIX-}
while [ "$#" -gt 0 ]; do
	case $1 in
	--prefix)
		if [ "$#" -lt 2 ] || [ -z "$2" ]; then
			usage
			exit 2
		fi
		prefix=$2
		shift 2
		;;
	*)
		usage
		exit 2
		;;
	esac
done
[ -n "$prefix" ] || prefix=$HOME/.local

case $0 in
*/*) script_dir=${0%/*} ;;
*) script_dir=. ;;
esac
source_dir=$(cd -P -- "$script_dir" && pwd -P) || fail "$script_dir"
version=$(cat "$source_dir/VERSION") || fail "$source_dir/VERSION"

share_dir=$prefix/share/project-path-gateway
mkdir -p -- "$prefix/bin" 2>/dev/null || fail "$prefix/bin"
mkdir -p -- "$share_dir" 2>/dev/null || fail "$share_dir"

# 원본을 같은 디렉터리의 임시 파일에 복사하고 권한을 정한 뒤 mv -f로 교체한다.
install_file() {
	temp="$2.ppg-install.$$"
	if cat -- "$1" >"$temp" 2>/dev/null && chmod "$3" "$temp" && mv -f -- "$temp" "$2"; then
		return 0
	fi
	rm -f -- "$temp"
	fail "$2"
}

install_file "$source_dir/bin/project-path-gateway" "$prefix/bin/project-path-gateway" 755
install_file "$source_dir/lib/project-path-gateway.sh" "$share_dir/project-path-gateway.sh" 644
install_file "$source_dir/VERSION" "$share_dir/VERSION" 644

manifest_temp="$share_dir/install-manifest.ppg-manifest.$$"
printf '%s\n' \
	bin/project-path-gateway \
	share/project-path-gateway/project-path-gateway.sh \
	share/project-path-gateway/VERSION \
	share/project-path-gateway/install-manifest >"$manifest_temp" 2>/dev/null || {
	rm -f -- "$manifest_temp"
	fail "$share_dir/install-manifest"
}
install_file "$manifest_temp" "$share_dir/install-manifest" 644
rm -f -- "$manifest_temp"

printf 'project-path-gateway: 설치 완료: %s (버전 %s)\n' "$prefix" "$version"
case ":${PATH-}:" in
*":$prefix/bin:"*) ;;
*)
	printf 'project-path-gateway: %s가 PATH에 없습니다. 셸 설정 파일에 다음 줄을 추가하세요:\n' "$prefix/bin"
	printf '  export PATH="%s/bin:$PATH"\n' "$prefix"
	;;
esac
