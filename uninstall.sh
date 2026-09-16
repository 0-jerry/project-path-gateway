#!/bin/sh
# project-path-gateway 제거 스크립트 (contracts/install.md 2절)
#
# 사용법: sh uninstall.sh [--prefix DIR]
#
# 설치 목록(install-manifest)에 적힌 파일만 지운다. 프로젝트 안 .tool/project-path-gateway/는 건드리지 않는다.

usage() {
	printf '사용법: sh uninstall.sh [--prefix DIR]\n' >&2
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

share_dir=$prefix/share/project-path-gateway
manifest=$share_dir/install-manifest
if [ ! -f "$manifest" ]; then
	printf 'project-path-gateway: 설치 기록이 없습니다: %s\n' "$prefix" >&2
	exit 1
fi

# 지우기 전에 목록 전체를 검사한다. 절대경로나 .. 세그먼트가 하나라도 있으면 아무것도 지우지 않는다.
while IFS= read -r entry || [ -n "$entry" ]; do
	case $entry in
	/*)
		printf 'project-path-gateway: 설치 목록에 절대경로가 있어 제거하지 않습니다: %s\n' "$entry" >&2
		exit 1
		;;
	esac
	case /$entry/ in
	*/../*)
		printf 'project-path-gateway: 설치 목록에 .. 세그먼트가 있어 제거하지 않습니다: %s\n' "$entry" >&2
		exit 1
		;;
	esac
done <"$manifest"

entries=$(cat "$manifest") || exit 1
printf '%s\n' "$entries" | while IFS= read -r entry; do
	[ -n "$entry" ] || continue
	rm -f -- "$prefix/$entry"
done
rmdir -- "$share_dir" 2>/dev/null

printf 'project-path-gateway: 제거 완료: %s\n' "$prefix"
