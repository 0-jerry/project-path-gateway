# 테스트 준비 함수
#
# 임시 프로젝트, 데이터 파일, 설치 PREFIX를 만들고 파일 시스템 변화를 비교하는 도우미다.

# 디렉터리의 물리 경로를 출력한다.
physical() {
	(cd -P -- "$1" && pwd -P)
}

# DIR/.tool/project-path-gateway/에 루트 표식 파일, 데이터 파일, 저장소 라이브러리 복사본을 만든다.
make_project() {
	mkdir -p "$1/.tool/project-path-gateway" || return 1
	printf '%s\n%s\n' \
		'# project-path-gateway 루트 표식 파일입니다. 이 파일을 담은 .tool/ 디렉터리의 상위 디렉터리가 프로젝트 루트입니다.' \
		'format=1' >"$1/.tool/project-path-gateway/.project-path-gateway"
	printf '%s' "${2-}" >"$1/.tool/project-path-gateway/project-path-gateway.conf"
	cp "$REPO_ROOT/lib/project-path-gateway.sh" "$1/.tool/project-path-gateway/project-path-gateway.sh"
}

# 데이터 파일 내용을 개행 추가 없이 쓴다.
write_conf() {
	printf '%s' "$2" >"$1/.tool/project-path-gateway/project-path-gateway.conf"
}

conf_path() {
	printf '%s\n' "$1/.tool/project-path-gateway/project-path-gateway.conf"
}

lib_path() {
	printf '%s\n' "$1/.tool/project-path-gateway/project-path-gateway.sh"
}

install_to() {
	sh "$REPO_ROOT/install.sh" --prefix "$1" >/dev/null 2>&1
}

# 기준 파일을 만들고 1초 기다린다. 이후 수정된 항목은 find -newer로 찾을 수 있다.
time_ref() {
	: >"$1"
	sleep 1
}

changed_since() {
	find "$2" -newer "$1" | LC_ALL=C sort
}

tree_list() {
	(cd "$1" && find . | LC_ALL=C sort)
}

# 테스트 셸로 스크립트를 실행한다. 추가 인자는 $1, $2...로 전달된다.
in_shell() {
	"$TEST_SHELL" -c "$@"
}
