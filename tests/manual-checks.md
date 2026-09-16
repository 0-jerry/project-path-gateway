# 수동 확인 절차

자동 사례(`sh tests/run.sh`)는 모든 파일 시스템 조회와 상태 변경을 대체물로 바꾼 dry-run으로 실행합니다. 이 문서는 실제
환경에서만 확인할 수 있는 동작을 사람이 확인하는 절차입니다. 추적 대조표 [traceability.md](./traceability.md)의 "수동 확인"
열이 이 문서의 절 번호를 가리킵니다.

## 공통 준비

- 모든 절은 저장소 루트에서 시작하고, 확인할 셸마다 한 번씩 실행합니다. `SH`에 대상 셸을 넣습니다.

```sh
SH=/bin/sh      # 두 번째 확인은 SH=dash
REPO=$(pwd -P)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ppg-manual.XXXXXX")
```

- 각 절이 끝나면 작업 디렉터리를 지웁니다. 권한을 바꾼 절은 절 안의 정리 명령을 먼저 실행합니다.

```sh
rm -rf "$WORK"
```

- 기대 결과의 `<WORK>`는 `$WORK`의 물리 경로(`cd -P "$WORK" && pwd -P`)입니다.

## 1. 시스템 포트 실제 동작

제품 코드의 시스템 포트(`project_path_gateway__sys_*`, `ppg__sys_*`)가 실제 명령으로 사례의 대체물 규칙과 같은 결과를 내는지
확인합니다.

```sh
mkdir -p "$WORK/real/dir" && : >"$WORK/real/file" && printf 'A=a\nB=b' >"$WORK/real/conf"
ln -s real "$WORK/link" && ln -s nope "$WORK/broken" && ln -s loop2 "$WORK/loop1" && ln -s loop1 "$WORK/loop2"
"$SH" -c '
. "$1/lib/project-path-gateway.sh"
w=$2
project_path_gateway__sys_is_dir "$w/link" && echo is_dir-link
project_path_gateway__sys_is_file "$w/real/file" && echo is_file
project_path_gateway__sys_exists "$w/broken" || echo broken-not-exists
project_path_gateway__sys_is_link "$w/broken" && echo broken-is-link
project_path_gateway__sys_exists "$w/loop1" || echo loop-not-exists
d=$(project_path_gateway__sys_physical_dir "$w/link/dir") && printf "physical=%s\n" "${d%x}"
t=$(project_path_gateway__sys_readlink "$w/link") && printf "readlink=%s\n" "${t%x}"
project_path_gateway__sys_read_lines "$w/real/conf"
' _ "$REPO" "$WORK"
```

기대 결과(stdout):

```text
is_dir-link
is_file
broken-not-exists
broken-is-link
loop-not-exists
physical=<WORK>/real/dir
readlink=real
A=a
B=b
```

전역 프로그램 포트는 다음으로 확인합니다.

```sh
: >"$WORK/real/.ppg-tmp.111.a" && : >"$WORK/real/.ppg-tmp.1.a" && : >"$WORK/real/.ppg-tmp.1110.a"
PPG_SOURCE_ONLY=1 "$SH" -c '
. "$1/bin/project-path-gateway"
ppg__sys_list_prefix "$2/real" .ppg-tmp.111.
ppg__sys_write_text "$2/real/w" "x y" && ppg__sys_link "$2/real/w" "$2/real/w2" && echo linked
ppg__sys_link "$2/real/w" "$2/real/w2" || echo link-exists-fails
ppg__sys_move "$2/real/w2" "$2/real/w3" && ppg__sys_remove "$2/real/w3" && ppg__sys_remove "$2/real/w3" && echo remove-twice
' _ "$REPO" "$WORK"
```

기대 결과: `.ppg-tmp.111.a`, `linked`, `link-exists-fails`, `remove-twice` 네 줄. `.ppg-tmp.1110.a`와 `.ppg-tmp.1.a`는
나오지 않습니다.

## 2. 실제 설치·재설치·제거

```sh
PREFIX_DIR="$WORK/prefix"
"$SH" install.sh --prefix "$PREFIX_DIR"
ls -l "$PREFIX_DIR/bin/project-path-gateway" "$PREFIX_DIR/share/project-path-gateway"
cat "$PREFIX_DIR/share/project-path-gateway/install-manifest"
printf 'old\n' >"$PREFIX_DIR/share/project-path-gateway/project-path-gateway.sh"
"$SH" install.sh --prefix "$PREFIX_DIR" >/dev/null && cmp lib/project-path-gateway.sh "$PREFIX_DIR/share/project-path-gateway/project-path-gateway.sh" && echo replaced
: >"$PREFIX_DIR/bin/other-tool"
"$SH" uninstall.sh --prefix "$PREFIX_DIR"
ls -A "$PREFIX_DIR" "$PREFIX_DIR/bin"
```

기대 결과:

- 첫 설치 stdout 첫 줄 `project-path-gateway: 설치 완료: <WORK>/prefix (버전 <VERSION 내용>)`, PATH에 없으면 `export PATH=...` 안내.
- 실행 파일 권한 `-rwxr-xr-x`, `share/project-path-gateway/` 세 파일 권한 `-rw-r--r--`.
- 설치 목록 네 줄: `bin/project-path-gateway`, `share/project-path-gateway/project-path-gateway.sh`,
  `share/project-path-gateway/VERSION`, `share/project-path-gateway/install-manifest`.
- `replaced` 출력.
- 제거 stdout `project-path-gateway: 제거 완료: <WORK>/prefix`, 이후 `ls` 결과는 `bin`(과 빈 `share`) 및 `other-tool`만.

설치 쓰기 실패(root가 아닌 사용자):

```sh
mkdir -p "$WORK/locked" && chmod 555 "$WORK/locked"
"$SH" install.sh --prefix "$WORK/locked/prefix"; echo "status=$?"
chmod 755 "$WORK/locked"
```

기대 결과: stderr `project-path-gateway: 설치 실패: <WORK>/locked/prefix/bin`, `status=1`.

## 3. 전역 프로그램 실제 초기화·재실행·쓰기 실패

```sh
"$SH" install.sh --prefix "$WORK/prefix" >/dev/null
PPG="$WORK/prefix/bin/project-path-gateway"
mkdir -p "$WORK/project"
"$PPG" init "$WORK/project"
ls -A "$WORK/project/.tool/project-path-gateway"
printf 'APP_CONFIG=config/app.json\n' >>"$WORK/project/.tool/project-path-gateway/project-path-gateway.conf"
ls -i "$WORK/project/.tool/project-path-gateway/project-path-gateway.conf"
"$PPG" init "$WORK/project"
ls -i "$WORK/project/.tool/project-path-gateway/project-path-gateway.conf"
grep -r -F -e "$WORK" -e "$HOME" "$WORK/project/.tool" || echo no-machine-values
```

기대 결과:

- 첫 실행 stdout `생성:` 세 줄과 `초기화 완료: <WORK>/project`, 도구 디렉터리에 세 파일만 있음(임시 파일 없음).
- 재실행 stdout `유지:` 두 줄, `교체: .tool/project-path-gateway/project-path-gateway.sh`, 데이터 파일 inode가 같음.
- `no-machine-values` 출력.

쓰기 실패(root가 아닌 사용자):

```sh
rm "$WORK/project/.tool/project-path-gateway/project-path-gateway.sh"
chmod 555 "$WORK/project/.tool/project-path-gateway"
"$PPG" init "$WORK/project"; echo "status=$?"
chmod 755 "$WORK/project/.tool/project-path-gateway"
ls -A "$WORK/project/.tool/project-path-gateway"
```

기대 결과: stderr `project-path-gateway: init: 파일을 쓰지 못했습니다: <WORK>/project/.tool/project-path-gateway/project-path-gateway.sh`,
`status=1`, 표식·데이터 파일 유지, `.ppg-tmp.` 파일 없음. 공백·한글 경로(`"$WORK/내 프로젝트 폴더"`)로 한 번 더 반복합니다.

## 4. 신호에 따른 임시 파일 정리

`dash`는 신호로 끝날 때 `EXIT` trap을 실행하지 않으므로 전역 프로그램은 `INT`·`TERM` trap을 따로 겁니다(기능 001 research R-10).

```sh
target="$WORK/공백 있는 대상"
mkdir -p "$target/.tool/project-path-gateway"
for sig in TERM INT exit; do
	rm -f "$target/.tool/project-path-gateway/".ppg-tmp.*
	"$SH" -c '
		PPG_SOURCE_ONLY=1
		. "$1"
		ppg__if_set_traps "$2"
		tool="$2/.tool/project-path-gateway"
		: >"$tool/.ppg-tmp.$$.x"
		: >"$tool/.ppg-tmp.1.x"
		case $3 in
		exit) exit 0 ;;
		*) kill -"$3" $$ ;;
		esac
		sleep 2
	' _ "$REPO/bin/project-path-gateway" "$target" "$sig"
	printf '%s status=%s left=%s\n' "$sig" "$?" "$(ls -A "$target/.tool/project-path-gateway" | tr '\n' ' ')"
done
```

기대 결과:

```text
TERM status=143 left=.ppg-tmp.1.x 
INT status=130 left=.ppg-tmp.1.x 
exit status=0 left=.ppg-tmp.1.x 
```

이 절은 대화형 터미널의 포그라운드에서 실행합니다. 백그라운드 작업(`&`)은 `SIGINT`가 무시 상태로 상속되어 `INT` 결과가 달라집니다.

## 5. 권한 거부 경로 검증

root가 아닌 사용자로 실행합니다.

```sh
root="$WORK/root"
mkdir -p "$root/.tool/project-path-gateway" "$root/locked"
printf '%s\n' '# marker' 'format=1' >"$root/.tool/project-path-gateway/.project-path-gateway"
printf 'LOCKED=locked/file\n' >"$root/.tool/project-path-gateway/project-path-gateway.conf"
: >"$root/locked/file"
chmod 000 "$root/locked"
"$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" && project_path_gateway_verify' _ "$REPO" "$root"; echo "status=$?"
chmod 755 "$root/locked"
chmod 000 "$root/.tool/project-path-gateway/.project-path-gateway"
"$SH" -c '. "$1/lib/project-path-gateway.sh"; cd "$2" && project_path_gateway_init && printf "%s\n" "$PROJECT_PATH_GATEWAY_ROOT"' _ "$REPO" "$root"
chmod 644 "$root/.tool/project-path-gateway/.project-path-gateway"
```

기대 결과: stderr `project-path-gateway: 누락: LOCKED=locked/file`, `project-path-gateway: 검증 실패 1건`, `status=1`.
읽을 수 없는 표식 파일도 루트로 인정되어 `<WORK>/root`가 출력됩니다.

## 6. clone·이동 후 동작

```sh
"$SH" install.sh --prefix "$WORK/prefix" >/dev/null
mkdir -p "$WORK/origin/config" && : >"$WORK/origin/config/app.json"
"$WORK/prefix/bin/project-path-gateway" init "$WORK/origin" >/dev/null
printf 'APP_CONFIG=config/app.json\n' >>"$WORK/origin/.tool/project-path-gateway/project-path-gateway.conf"
git -C "$WORK/origin" init -q && git -C "$WORK/origin" add -A &&
	git -C "$WORK/origin" -c user.name=tester -c user.email=tester@example.invalid -c commit.gpgsign=false commit -q -m init
git clone -q "$WORK/origin" "$WORK/clone/복제 위치"
mv "$WORK/origin" "$WORK/moved"
"$SH" uninstall.sh --prefix "$WORK/prefix" >/dev/null
for p in "$WORK/clone/복제 위치" "$WORK/moved"; do
	(cd "$p" && "$SH" -c '. ./.tool/project-path-gateway/project-path-gateway.sh && project_path_gateway_init && project_path_gateway_get APP_CONFIG && project_path_gateway_verify')
done
```

기대 결과: 위치마다 `<물리 경로>/config/app.json`과 `project-path-gateway: 검증 통과 1건`, 반환 0.

## 7. 설치된 다국어 로캘에서의 키 판정

```sh
locale -a | grep -i 'utf-\?8' | head -3
for loc in $(locale -a | grep -i 'utf-\?8' | head -3) C; do
	LC_ALL=$loc "$SH" -c '
		. "$1/lib/project-path-gateway.sh"
		for k in A A_1 AÉ a A-B Ａ; do
			if project_path_gateway__domain_is_valid_key "$k"; then r=valid; else r=invalid; fi
			printf "%s:%s " "$k" "$r"
		done
		echo
	' _ "$REPO"
done
```

기대 결과: 모든 로캘에서 같은 줄 `A:valid A_1:valid AÉ:invalid a:invalid A-B:invalid Ａ:invalid `.

## 8. pre-commit 훅의 실제 커밋 중단

```sh
repo="$WORK/repo"
mkdir -p "$repo/config" && : >"$repo/config/app.json"
git init -q "$repo"
"$SH" install.sh --prefix "$WORK/prefix" >/dev/null
"$WORK/prefix/bin/project-path-gateway" init "$repo" >/dev/null
printf 'APP_CONFIG=config/app.json\n' >>"$repo/.tool/project-path-gateway/project-path-gateway.conf"
awk '$0 == "<!-- example: pre-commit -->" { f = 1; next } f == 1 && $0 == "```sh" { f = 2; next } f == 2 && $0 == "```" { exit } f == 2' README.md >"$repo/.git/hooks/pre-commit"
chmod 755 "$repo/.git/hooks/pre-commit"
g() { git -C "$repo" -c core.hooksPath=.git/hooks -c commit.gpgsign=false -c user.name=tester -c user.email=tester@example.invalid "$@"; }
g add -A && g commit -q -m init; echo "first=$?"
rm "$repo/config/app.json"
g commit -q -a -m '경로 삭제'; echo "second=$?"
g rev-list --count HEAD
```

기대 결과: 첫 커밋 stderr에 `project-path-gateway: 검증 통과 1건`, `first=0`. 두 번째 커밋 stderr에
`project-path-gateway: 누락: APP_CONFIG=config/app.json`과 `project-path-gateway: 검증 실패 1건`, `second=1`, 커밋 수 `1`.
훅은 `/bin/sh`로 실행되므로 `dash` 확인은 훅 첫 줄을 `#!/usr/bin/env dash`로 바꿔 반복합니다.

## 9. 항목 200개 검증 시간

```sh
root="$WORK/root200"
mkdir -p "$root/.tool/project-path-gateway" "$root/dir"
printf '%s\n' '# marker' 'format=1' >"$root/.tool/project-path-gateway/.project-path-gateway"
i=0; while [ "$i" -lt 200 ]; do printf 'KEY_%s=dir/file_%s\n' "$i" "$i"; : >"$root/dir/file_$i"; i=$((i + 1)); done >"$root/.tool/project-path-gateway/project-path-gateway.conf"
time "$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" && project_path_gateway_verify' _ "$REPO" "$root"
```

기대 결과: stdout `project-path-gateway: 검증 통과 200건`, 반환 0, 경과 시간 2초 이내(초과하면 기록만 남깁니다).

## 10. 검증 리포트 파일 실제 쓰기

기능 003(`project_path_gateway_verify [REPORT_FILE]`)의 실제 파일 쓰기를 확인합니다. root가 아닌 사용자로 실행하고, 10.1부터 순서대로 실행합니다.

```sh
root="$WORK/root"
mkdir -p "$root/.tool/project-path-gateway" "$root/a" "$WORK/out"
printf '%s\n' '# marker' 'format=1' >"$root/.tool/project-path-gateway/.project-path-gateway"
printf 'A=a\nB=b\nC=c\n' >"$root/.tool/project-path-gateway/project-path-gateway.conf"
v() { "$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" || exit 2; shift 2; project_path_gateway_verify "$@"' _ "$REPO" "$root" "$@"; }
```

### 10.1 실패 리포트와 터미널 출력 동일성

```sh
v 2>"$WORK/plain.err"; echo "plain=$?"
v "$WORK/out/결과 리포트.txt" 2>"$WORK/report.err"; echo "report=$?"
cmp "$WORK/plain.err" "$WORK/report.err" && cmp "$WORK/report.err" "$WORK/out/결과 리포트.txt" && echo 동일
cat "$WORK/out/결과 리포트.txt"
```

기대 결과: `plain=1`, `report=1`, `동일`. 리포트는 `project-path-gateway: 누락: B=b`, `project-path-gateway: 누락: C=c`,
`project-path-gateway: 검증 실패 2건` 세 줄입니다.

### 10.2 통과 리포트와 덮어쓰기

```sh
: >"$root/b"; : >"$root/c"
v "$WORK/out/결과 리포트.txt"; echo "status=$?"
cat "$WORK/out/결과 리포트.txt"
```

기대 결과: stdout `project-path-gateway: 검증 통과 3건`, `status=0`, 리포트는 같은 한 줄만 담습니다(이전 실패 줄 없음).

### 10.3 파일 링크 리포트 위치

```sh
printf 'keep\n' >"$WORK/out/target.txt"; ln -s target.txt "$WORK/out/link.txt"
v "$WORK/out/link.txt" >/dev/null; echo "status=$?"
[ -L "$WORK/out/link.txt" ] && echo 링크유지 || echo 링크교체
cat "$WORK/out/target.txt"
```

기대 결과: `status=0`, `링크교체`, `keep`(링크 대상은 바뀌지 않음).

### 10.4 리포트 쓰기 실패

```sh
mkdir "$WORK/locked" "$WORK/dir-target" && chmod 555 "$WORK/locked"
ln -s "$WORK/dir-target" "$WORK/dir-link"
for r in "$WORK/none/report.txt" "$WORK/locked/report.txt" "$WORK/dir-target" "$WORK/dir-link" "$WORK/out/"; do
	v "$r" >/dev/null; echo "status=$?"
done
ls -A "$WORK/locked" "$WORK/dir-target"; [ -L "$WORK/dir-link" ] && echo 디렉터리링크유지
find "$WORK" -name '.ppg-report.*' | wc -l
chmod 755 "$WORK/locked"
```

기대 결과: 경로마다 stderr `project-path-gateway: project_path_gateway_verify: 리포트 파일을 쓸 수 없습니다: <경로>`와
`status=2`(5번), `ls` 출력 없음, `디렉터리링크유지`, 임시 파일 수 `0`.

### 10.5 리포트 미지정 검증의 무변경

```sh
before=$(cd "$WORK" && find . -exec ls -ld {} + | LC_ALL=C sort)
v >/dev/null
after=$(cd "$WORK" && find . -exec ls -ld {} + | LC_ALL=C sort)
[ "$before" = "$after" ] && echo 무변경
```

기대 결과: `무변경`.

### 10.6 서로 다른 셸 프로세스의 동시 실행

```sh
printf 'project-path-gateway: 검증 통과 3건\n' >"$WORK/expected.txt"
i=0; while [ "$i" -lt 20 ]; do
	v "$WORK/out/concurrent.txt" >/dev/null & p1=$!
	v "$WORK/out/concurrent.txt" >/dev/null & p2=$!
	wait "$p1" "$p2"
	cmp -s "$WORK/out/concurrent.txt" "$WORK/expected.txt" || echo "불일치 $i"
	i=$((i + 1))
done
find "$WORK/out" -name '.ppg-report.*' | wc -l
```

기대 결과: `불일치` 줄 없음, 임시 파일 수 `0`. `v`는 실행마다 새 셸 프로세스를 띄우므로 서로 다른 PID를 씁니다.

### 10.7 신호 중단과 항목 200개 시간

```sh
big="$WORK/root200"
mkdir -p "$big/.tool/project-path-gateway" "$big/dir"
printf '%s\n' '# marker' 'format=1' >"$big/.tool/project-path-gateway/.project-path-gateway"
i=0; while [ "$i" -lt 200 ]; do printf 'KEY_%s=dir/file_%s\n' "$i" "$i"; : >"$big/dir/file_$i"; i=$((i + 1)); done >"$big/.tool/project-path-gateway/project-path-gateway.conf"
vb() { "$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" || exit 2; shift 2; project_path_gateway_verify "$@"' _ "$REPO" "$big" "$@"; }
t0=$(date +%s); vb >/dev/null; t1=$(date +%s); vb "$WORK/out/big.txt" >/dev/null; t2=$(date +%s)
echo "미지정 $((t1 - t0))초, 리포트 지정 $((t2 - t1))초"
printf 'old\n' >"$WORK/out/int.txt"
"$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" || exit 2; project_path_gateway_verify "$3"' _ "$REPO" "$big" "$WORK/out/int.txt" >/dev/null 2>&1 & p=$!
sleep 1; kill -TERM "$p"; wait "$p"; echo "status=$?"
head -1 "$WORK/out/int.txt"; ls -A "$WORK/out" | grep '^\.ppg-report\.' || echo 임시없음
```

기대 결과: 미지정과 리포트 지정 경과 시간 차이가 1초 이하(SC-005, 초 단위 측정, 초과하면 기록). 중단한 실행은 `status=143`이고(검증이 1초 안에 끝났으면 0), `int.txt` 첫 줄이 `old` 또는
`project-path-gateway: 검증 통과 200건`이고, 반쯤 쓴 내용은 없습니다. 쓰기와 옮기기 사이에 중단된 경우에만 `.ppg-report.<PID>.int.txt`
임시 파일이 남을 수 있으며 그 이름을 기록합니다.
