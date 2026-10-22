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
- 실행 파일 권한 `-rwxr-xr-x`, `share/project-path-gateway/` 네 파일(`SKILL.md`, `VERSION`, `install-manifest`, 라이브러리) 권한 `-rw-r--r--`.
- 설치 목록 다섯 줄: `bin/project-path-gateway`, `share/project-path-gateway/project-path-gateway.sh`,
  `share/project-path-gateway/VERSION`, `share/project-path-gateway/SKILL.md`, `share/project-path-gateway/install-manifest`.
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
ls -A "$WORK/project/.tools/project-path-gateway"
printf 'APP_CONFIG=config/app.json\n' >>"$WORK/project/.tools/project-path-gateway/project-path-gateway.files.conf"
ls -i "$WORK/project/.tools/project-path-gateway/project-path-gateway.files.conf"
"$PPG" init "$WORK/project"
ls -i "$WORK/project/.tools/project-path-gateway/project-path-gateway.files.conf"
grep -r -F -e "$WORK" -e "$HOME" "$WORK/project/.tools" || echo no-machine-values
```

기대 결과:

- 첫 실행 stdout `생성:` 다섯 줄(표식·디렉터리 데이터·파일 데이터·라이브러리·`SKILL.md`)과 `초기화 완료: <WORK>/project`,
  도구 디렉터리에 네 파일만 있음(임시 파일 없음). stderr 출력 없음(1.x 데이터 파일이 없으므로 안내 없음).
- 재실행 stdout `유지:` 세 줄, `교체: .tools/project-path-gateway/project-path-gateway.sh`,
  `교체: .agents/skills/project-path-gateway/SKILL.md`, 파일 데이터 파일 inode가 같음.
- `no-machine-values` 출력.

쓰기 실패(root가 아닌 사용자):

```sh
rm "$WORK/project/.tools/project-path-gateway/project-path-gateway.sh"
chmod 555 "$WORK/project/.tools/project-path-gateway"
"$PPG" init "$WORK/project"; echo "status=$?"
chmod 755 "$WORK/project/.tools/project-path-gateway"
ls -A "$WORK/project/.tools/project-path-gateway"
```

기대 결과: stderr `project-path-gateway: init: 파일을 쓰지 못했습니다: <WORK>/project/.tools/project-path-gateway/project-path-gateway.sh`,
`status=1`, 표식·두 데이터 파일 유지, `.ppg-tmp.` 파일 없음. 공백·한글 경로(`"$WORK/내 프로젝트 폴더"`)로 한 번 더 반복합니다.

## 4. 신호에 따른 임시 파일 정리

`dash`는 신호로 끝날 때 `EXIT` trap을 실행하지 않으므로 전역 프로그램은 `INT`·`TERM` trap을 따로 겁니다(기능 001 research R-10).

```sh
target="$WORK/공백 있는 대상"
mkdir -p "$target/.tools/project-path-gateway"
for sig in TERM INT exit; do
	rm -f "$target/.tools/project-path-gateway/".ppg-tmp.*
	"$SH" -c '
		PPG_SOURCE_ONLY=1
		. "$1"
		ppg__if_set_traps "$2"
		tool="$2/.tools/project-path-gateway"
		: >"$tool/.ppg-tmp.$$.x"
		: >"$tool/.ppg-tmp.1.x"
		case $3 in
		exit) exit 0 ;;
		*) kill -"$3" $$ ;;
		esac
		sleep 2
	' _ "$REPO/bin/project-path-gateway" "$target" "$sig"
	printf '%s status=%s left=%s\n' "$sig" "$?" "$(ls -A "$target/.tools/project-path-gateway" | tr '\n' ' ')"
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
mkdir -p "$root/.tools/project-path-gateway" "$root/locked"
printf '%s\n' '# marker' 'format=1' >"$root/.tools/project-path-gateway/.project-path-gateway"
: >"$root/.tools/project-path-gateway/project-path-gateway.dirs.conf"
printf 'LOCKED=locked/file.txt\n' >"$root/.tools/project-path-gateway/project-path-gateway.files.conf"
: >"$root/locked/file.txt"
chmod 000 "$root/locked"
"$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" && project_path_gateway_verify' _ "$REPO" "$root"; echo "status=$?"
chmod 755 "$root/locked"
chmod 000 "$root/.tools/project-path-gateway/.project-path-gateway"
"$SH" -c '. "$1/lib/project-path-gateway.sh"; cd "$2" && project_path_gateway_init && printf "%s\n" "$PROJECT_PATH_GATEWAY_ROOT"' _ "$REPO" "$root"
chmod 644 "$root/.tools/project-path-gateway/.project-path-gateway"
```

기대 결과: stderr `project-path-gateway: 누락: LOCKED=locked/file.txt`, `project-path-gateway: 검증 실패 1건`, `status=1`.
읽을 수 없는 표식 파일도 루트로 인정되어 `<WORK>/root`가 출력됩니다.

## 6. clone·이동 후 동작

```sh
"$SH" install.sh --prefix "$WORK/prefix" >/dev/null
mkdir -p "$WORK/origin/config" && : >"$WORK/origin/config/app.json"
"$WORK/prefix/bin/project-path-gateway" init "$WORK/origin" >/dev/null
printf 'APP_CONFIG=config/app.json\n' >>"$WORK/origin/.tools/project-path-gateway/project-path-gateway.files.conf"
git -C "$WORK/origin" init -q && git -C "$WORK/origin" add -A &&
	git -C "$WORK/origin" -c user.name=tester -c user.email=tester@example.invalid -c commit.gpgsign=false commit -q -m init
git clone -q "$WORK/origin" "$WORK/clone/복제 위치"
mv "$WORK/origin" "$WORK/moved"
"$SH" uninstall.sh --prefix "$WORK/prefix" >/dev/null
for p in "$WORK/clone/복제 위치" "$WORK/moved"; do
	(cd "$p" && "$SH" -c '. ./.tools/project-path-gateway/project-path-gateway.sh && project_path_gateway_init && project_path_gateway_file APP_CONFIG && project_path_gateway_verify')
done
```

기대 결과: 위치마다 `<물리 경로>/config/app.json`과 `project-path-gateway: 검증 통과 3건`(기본 디렉터리 항목 두 개 포함), 반환 0.

## 7. 설치된 다국어 로캘에서의 키 판정

```sh
locale -a | grep -i 'utf-\?8' | head -3
for loc in $(locale -a | grep -i 'utf-\?8' | head -3) C; do
	LC_ALL=$loc "$SH" -c '
		. "$1/lib/project-path-gateway.sh"
		for k in A A_1 AÉ a A-B Ａ; do
			if project_path_gateway__domain_key_is_valid "$k"; then r=valid; else r=invalid; fi
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
printf 'APP_CONFIG=config/app.json\n' >>"$repo/.tools/project-path-gateway/project-path-gateway.files.conf"
awk '$0 == "<!-- example: pre-commit -->" { f = 1; next } f == 1 && $0 == "```sh" { f = 2; next } f == 2 && $0 == "```" { exit } f == 2' README.md >"$repo/.git/hooks/pre-commit"
chmod 755 "$repo/.git/hooks/pre-commit"
g() { git -C "$repo" -c core.hooksPath=.git/hooks -c commit.gpgsign=false -c user.name=tester -c user.email=tester@example.invalid "$@"; }
g add -A && g commit -q -m init; echo "first=$?"
rm "$repo/config/app.json"
g commit -q -a -m '경로 삭제'; echo "second=$?"
g rev-list --count HEAD
```

기대 결과: 첫 커밋 stderr에 `project-path-gateway: 검증 통과 3건`(기본 디렉터리 항목 두 개 포함), `first=0`. 두 번째 커밋 stderr에
`project-path-gateway: 누락: APP_CONFIG=config/app.json`과 `project-path-gateway: 검증 실패 1건`, `second=1`, 커밋 수 `1`.
훅은 `/bin/sh`로 실행되므로 `dash` 확인은 훅 첫 줄을 `#!/usr/bin/env dash`로 바꿔 반복합니다.

## 9. 항목 200개 처리 시간과 변경 전후 비교

기능 005부터는 절대 시간(2초) 대신 변경 전 라이브러리와의 비교로 판정합니다(기능 005 SC-005). 변경 전 기준은 비교하려는 커밋의
라이브러리입니다(기능 005는 `07f2122`, 기능 007은 기능 005 최종 `0d52800`). 두 라이브러리를 번갈아 5회씩 실행하고 중앙값을 비교합니다.
시간 측정에만 `perl`을 씁니다.

기능 007부터 데이터 파일이 두 개이므로 변경 전(1.x)은 항목 200개를 데이터 파일 하나에, 변경 후(2.x)는 디렉터리 100개·파일 100개를
두 데이터 파일에 나눠 담습니다. 조회·등록은 파일 항목(`KEY_199`, `dir/new.txt`)으로 잽니다.

```sh
BASE=0d52800
git show "$BASE:lib/project-path-gateway.sh" >"$WORK/before.sh"
old="$WORK/old200"; new="$WORK/new200"
for r in "$old" "$new"; do
	mkdir -p "$r/.tools/project-path-gateway" "$r/dir"
	printf '%s\n' '# marker' 'format=1' >"$r/.tools/project-path-gateway/.project-path-gateway"
done
i=0; while [ "$i" -lt 200 ]; do printf 'KEY_%s=dir/file_%s\n' "$i" "$i"; : >"$old/dir/file_$i"; i=$((i + 1)); done >"$old/.tools/project-path-gateway/project-path-gateway.conf"
i=0; while [ "$i" -lt 100 ]; do printf 'KEY_%s=dir/d_%s\n' "$i" "$i"; mkdir -p "$new/dir/d_$i"; i=$((i + 1)); done >"$new/.tools/project-path-gateway/project-path-gateway.dirs.conf"
i=100; while [ "$i" -lt 200 ]; do printf 'KEY_%s=dir/file_%s.txt\n' "$i" "$i"; : >"$new/dir/file_$i.txt"; i=$((i + 1)); done >"$new/.tools/project-path-gateway/project-path-gateway.files.conf"
cp "$old/.tools/project-path-gateway/project-path-gateway.conf" "$WORK/old.conf"
cp "$new/.tools/project-path-gateway/project-path-gateway.files.conf" "$WORK/new.files.conf"
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
run_old() { # $1 셸, $2 동작
	cp "$WORK/old.conf" "$old/.tools/project-path-gateway/project-path-gateway.conf"
	a=$(now)
	"$1" -c '. "$1"; project_path_gateway_init "$2" || exit 2
		case $3 in verify) project_path_gateway_verify ;; get) project_path_gateway_get KEY_199 ;; add) project_path_gateway_add NEW_KEY dir/new ;; esac' _ "$WORK/before.sh" "$old" "$2" >/dev/null 2>&1
	b=$(now); echo "$b - $a" | bc
}
run_new() { # $1 셸, $2 동작
	cp "$WORK/new.files.conf" "$new/.tools/project-path-gateway/project-path-gateway.files.conf"
	a=$(now)
	"$1" -c '. "$1"; project_path_gateway_init "$2" || exit 2
		case $3 in verify) project_path_gateway_verify ;; get) project_path_gateway_file KEY_199 ;; add) project_path_gateway_add_file NEW_KEY dir/new.txt ;; esac' _ "$REPO/lib/project-path-gateway.sh" "$new" "$2" >/dev/null 2>&1
	b=$(now); echo "$b - $a" | bc
}
med() { LC_ALL=C sort -n | sed -n 3p; }
for sh in /bin/sh dash; do for op in verify get add; do
	: >"$WORK/b"; : >"$WORK/a"
	n=0; while [ "$n" -lt 5 ]; do run_old "$sh" "$op" >>"$WORK/b"; run_new "$sh" "$op" >>"$WORK/a"; n=$((n + 1)); done
	echo "$sh $op 변경 전 $(med <"$WORK/b") 변경 후 $(med <"$WORK/a")"
done; done
```

기대 결과: 여섯 줄(두 셸 × 초기화+검증·초기화+조회·초기화+등록). 판정 기준은 기능마다 정합니다. 기능 007은 조회·등록이 변경 전 이하,
초기화+검증이 변경 전의 110% 이내입니다(기능 007 `perf.md`). 초기화+검증의 stdout은 `project-path-gateway: 검증 통과 200건`,
반환 0입니다. 2초를 넘는 값은 실패로 보지 않고 기록만 남깁니다.

기록 형식:

| 날짜 | 기준 커밋 | 셸 | 동작 | 변경 전(초) | 변경 후(초) |
|---|---|---|---|---|---|

## 10. 검증 리포트 파일 실제 쓰기

기능 003(`project_path_gateway_verify [REPORT_FILE]`)의 실제 파일 쓰기를 확인합니다. root가 아닌 사용자로 실행하고, 10.1부터 순서대로 실행합니다.

```sh
root="$WORK/root"
mkdir -p "$root/.tools/project-path-gateway" "$root/a" "$WORK/out"
printf '%s\n' '# marker' 'format=1' >"$root/.tools/project-path-gateway/.project-path-gateway"
printf 'A=a\nB=b\nC=c\n' >"$root/.tools/project-path-gateway/project-path-gateway.dirs.conf"
: >"$root/.tools/project-path-gateway/project-path-gateway.files.conf"
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
mkdir "$root/b" "$root/c"
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
mkdir -p "$big/.tools/project-path-gateway" "$big/dir"
printf '%s\n' '# marker' 'format=1' >"$big/.tools/project-path-gateway/.project-path-gateway"
: >"$big/.tools/project-path-gateway/project-path-gateway.dirs.conf"
i=0; while [ "$i" -lt 200 ]; do printf 'KEY_%s=dir/file_%s.txt\n' "$i" "$i"; : >"$big/dir/file_$i.txt"; i=$((i + 1)); done >"$big/.tools/project-path-gateway/project-path-gateway.files.conf"
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

## 11. 경로 항목 등록·갱신 실제 쓰기

기능 004의 실제 파일 쓰기를 확인합니다. 기능 007부터 등록·갱신은 종류별 함수(`project_path_gateway_add_dir`, `_add_file`,
`_update_dir`, `_update_file`)이고, 11.2~11.7은 디렉터리 데이터 파일로, 11.8은 파일 데이터 파일과 종류 규칙으로 확인합니다. dry-run 사례는
호출 사이에 파일 상태가 이어지지 않으므로, 등록·갱신 뒤 연속 조회·검증은 이 절에서 확인합니다. root가 아닌 사용자로 실행하고,
11.1부터 순서대로 실행합니다.

```sh
root="$WORK/root"
tool="$root/.tools/project-path-gateway"
conf="$tool/project-path-gateway.dirs.conf"
fconf="$tool/project-path-gateway.files.conf"
mkdir -p "$tool" "$root/docs"
printf '%s\n' '# marker' 'format=1' >"$tool/.project-path-gateway"
printf '# 경로 항목\n' >"$conf"
: >"$fconf"
g() { "$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" || exit 2; shift 2; "$@"' _ "$REPO" "$root" "$@"; }
tmpcount() { ls -A "$tool" | grep -c '^\.ppg-tmp\.'; }
```

### 11.1 새 시스템 포트 실제 동작

```sh
printf 'A=a\nB=b' >"$WORK/raw" && chmod 640 "$WORK/raw"
"$SH" -c '
. "$1/lib/project-path-gateway.sh"
w=$2
t=$(project_path_gateway__sys_read_file "$w/raw") && printf "%s" "${t%x}" | od -c | tail -2 | head -1
project_path_gateway__sys_is_writable "$w/raw" && echo writable
project_path_gateway__sys_copy_preserve "$w/raw" "$w/copy" && echo copied
' _ "$REPO" "$WORK"
ls -l "$WORK/copy" | cut -c1-10
chmod 444 "$WORK/raw" && "$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway__sys_is_writable "$2/raw" || echo not-writable' _ "$REPO" "$WORK"
```

기대 결과: `od` 줄이 `b`로 끝나고 끝에 `\n`이 없음, `writable`, `copied`, `-rw-r-----`, `not-writable`.

### 11.2 등록 뒤 연속 조회·검증 (US1, SC-001, SC-004)

```sh
g project_path_gateway_add_dir DOCS_DIR docs; echo "add=$?"
g project_path_gateway_add_dir NEW_DIR 'not yet'; echo "add2=$?"
g project_path_gateway_dir DOCS_DIR
g project_path_gateway_verify; echo "verify=$?"
cat "$conf"
```

기대 결과: `add=0`, `add2=0`(출력 없음), `<WORK>/root/docs`, stderr `project-path-gateway: 누락: NEW_DIR=not yet`과
`project-path-gateway: 검증 실패 1건`, `verify=1`(규칙 위반 보고 없음). 파일은 `# 경로 항목`, `DOCS_DIR=docs`, `NEW_DIR=not yet` 세 줄입니다.

### 11.3 중복 등록 거부 (US2, SC-002)

```sh
before=$(cksum <"$conf")
g project_path_gateway_add_dir DOCS_DIR manual; echo "status=$?"
g project_path_gateway_add_file DOCS_DIR docs.txt; echo "status=$?"
[ "$before" = "$(cksum <"$conf")" ] && echo 무변경
```

기대 결과: stderr `project-path-gateway: project_path_gateway_add_dir: 이미 등록된 키입니다: DOCS_DIR`와 `status=2`,
`project-path-gateway: project_path_gateway_add_file: 이미 등록된 키입니다: DOCS_DIR`와 `status=2`(키는 두 파일을 합쳐 유일), `무변경`.

### 11.4 가운데 키 갱신과 파일 끝 개행 유지 (US3, SC-003)

```sh
printf '# 경로 항목\n\nA_DIR=a\nB_DIR=b\n\nC_DIR=c\n' >"$conf"
printf '# 경로 항목\n\nA_DIR=a\nB_DIR=new/b\n\nC_DIR=c\n' >"$WORK/expected"
g project_path_gateway_update_dir B_DIR new/b; echo "status=$?"
cmp "$conf" "$WORK/expected" && echo 대상줄만변경
g project_path_gateway_dir B_DIR
printf 'A_DIR=a\nB_DIR=b' >"$conf"
g project_path_gateway_update_dir B_DIR x; echo "status=$?"
od -c "$conf" | tail -2 | head -1
g project_path_gateway_update_dir X_DIR x; echo "status=$?"
```

기대 결과: `status=0`, `대상줄만변경`, `<WORK>/root/new/b`, `status=0`, `od` 줄이 `x`로 끝나고 `\n` 없음,
stderr `등록되지 않은 키입니다: X_DIR`와 `status=2`.

### 11.5 모드 유지, 읽기 전용 파일, 링크, 도구 디렉터리 쓰기 불가 (US4, FR-030~FR-034)

```sh
printf 'A_DIR=a\n' >"$conf" && chmod 640 "$conf"
touch -t 200001010000 "$conf"
g project_path_gateway_add_dir B_DIR b; echo "status=$?"
ls -l "$conf" | cut -c1-10; find "$conf" -newermt 2000-01-02 | grep -q . && echo 수정시각갱신
chmod 444 "$conf"; before=$(cksum <"$conf")
g project_path_gateway_add_dir C_DIR c; echo "readonly=$?"
g project_path_gateway_update_dir A_DIR a; echo "same-path=$?"
[ "$before" = "$(cksum <"$conf")" ] && echo 무변경
chmod 644 "$conf"
mv "$conf" "$root/real.conf" && ln -s ../../real.conf "$conf"
g project_path_gateway_add_dir C_DIR c; echo "link=$?"
[ -L "$conf" ] && echo 링크유지
rm "$conf" && mv "$root/real.conf" "$conf"
chmod 555 "$tool"
g project_path_gateway_add_dir C_DIR c; echo "dir-readonly=$?"
chmod 755 "$tool"
[ "$before" = "$(cksum <"$conf")" ] && echo 무변경
echo "임시파일 $(tmpcount)개"
```

기대 결과: `status=0`, `-rw-r-----`, `수정시각갱신`. stderr `데이터 파일에 쓰기 권한이 없습니다: <conf>`와 `readonly=2`,
`same-path=0`, `무변경`. stderr `데이터 파일이 심볼릭 링크라 바꿀 수 없습니다: <conf>`와 `link=2`, `링크유지`.
stderr `데이터 파일을 쓸 수 없습니다: <conf>`와 `dir-readonly=2`, `무변경`, `임시파일 0개`.

### 11.6 서로 다른 셸 프로세스의 동시 등록 (경계 사례)

```sh
printf 'A_DIR=a\n' >"$conf"
i=0; while [ "$i" -lt 10 ]; do
	g project_path_gateway_add_dir "P_$i" p & p1=$!
	g project_path_gateway_add_dir "Q_$i" q & p2=$!
	wait "$p1" "$p2"
	i=$((i + 1))
done
g project_path_gateway_dir A_DIR >/dev/null && echo 규칙유지
echo "항목 $(grep -c '=' "$conf")줄, 임시파일 $(tmpcount)개"
```

기대 결과: `규칙유지`(데이터 파일 규칙 위반 없음), 항목은 1~21줄(동시 실행에서 한쪽 변경이 빠질 수 있음), `임시파일 0개`.

### 11.7 신호 중단과 항목 200개 시간 (FR-030, SC-006)

```sh
i=1; while [ "$i" -le 200 ]; do printf 'KEY_%s=dir/%s\n' "$i" "$i"; i=$((i + 1)); done >"$conf"
t0=$(date +%s); g project_path_gateway_dir KEY_200 >/dev/null; t1=$(date +%s)
g project_path_gateway_update_dir KEY_200 moved/200; t2=$(date +%s)
echo "조회 $((t1 - t0))초, 갱신 $((t2 - t1))초"
cp "$conf" "$WORK/before.conf"
"$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" || exit 2; project_path_gateway_add_dir LAST_DIR last' _ "$REPO" "$root" & p=$!
sleep 1; kill -TERM "$p" 2>/dev/null; wait "$p"; echo "status=$?"
if cmp -s "$conf" "$WORK/before.conf"; then echo 이전내용; elif tail -1 "$conf" | grep -qx 'LAST_DIR=last'; then echo 새내용; fi
echo "임시파일 $(tmpcount)개"
```

기대 결과: 조회와 갱신 경과 시간 차이가 1초 이하(SC-006, 초 단위 측정). 중단한 실행은 `status=143`(1초 안에 끝났으면 0)이고,
데이터 파일은 `이전내용` 또는 `새내용`입니다. 중단 대상은 함수로 감싸지 않고 `"$SH" -c`를 직접 백그라운드로 띄워야 `kill`이 등록 프로세스에 닿습니다. 임시 파일은 0개 또는 1개(복사와 교체 사이에 중단된 경우만)이며 남으면 이름을 기록합니다.

### 11.8 파일 항목과 종류 규칙 (기능 007 US1~US4)

```sh
printf 'A_DIR=a\n' >"$conf"; : >"$fconf"
mkdir -p "$root/a" "$root/config" && : >"$root/config/app.json" && : >"$root/Makefile"
g project_path_gateway_add_file APP_CONFIG config/app.json; echo "add_file=$?"
g project_path_gateway_file APP_CONFIG
g project_path_gateway_dir APP_CONFIG; echo "dir=$?"
g project_path_gateway_file A_DIR; echo "file=$?"
g project_path_gateway_add_file ROOT_MAKEFILE Makefile; echo "makefile=$?"
g project_path_gateway_add_dir APP_JSON config/app.json; echo "dir-shape=$?"
g project_path_gateway_update_file A_DIR a.txt; echo "update-kind=$?"
g project_path_gateway_update_file APP_CONFIG config/app.yaml; echo "update=$?"
cat "$conf" "$fconf"
mkdir "$root/config/app.yaml"
g project_path_gateway_verify; echo "verify=$?"
echo "임시파일 $(tmpcount)개"
```

기대 결과:

- `add_file=0`, `<WORK>/root/config/app.json`.
- stderr `project-path-gateway: project_path_gateway_dir: 디렉터리 키가 아닙니다(파일 데이터 파일에 등록됨): APP_CONFIG`와 `dir=2`.
- stderr `project-path-gateway: project_path_gateway_file: 파일 키가 아닙니다(디렉터리 데이터 파일에 등록됨): A_DIR`와 `file=2`.
- stderr `project-path-gateway: project_path_gateway_add_file: 파일 경로가 파일 모양이 아닙니다(이름.확장자 또는 .으로 시작하는 이름, 끝 / 없음): Makefile`와 `makefile=2`.
- stderr `project-path-gateway: project_path_gateway_add_dir: 디렉터리 경로가 파일 모양입니다(확장자가 있거나 .으로 시작): config/app.json`와 `dir-shape=2`.
- stderr `project-path-gateway: project_path_gateway_update_file: 파일 키가 아닙니다(디렉터리 데이터 파일에 등록됨): A_DIR`와 `update-kind=2`.
- `update=0`. 데이터 파일 내용은 `A_DIR=a`(디렉터리)와 `APP_CONFIG=config/app.yaml`(파일) 두 줄뿐입니다.
- 검증 stderr `project-path-gateway: 종류 불일치: APP_CONFIG=config/app.yaml (일반 파일이 아님)`과
  `project-path-gateway: 검증 실패 1건`, `verify=1`, `임시파일 0개`.

## 12. 기능 006 초기화 템플릿과 에이전트 스킬 (기능 006 SC-001~SC-003, SC-005)

```sh
"$SH" install.sh --prefix "$WORK/prefix" >/dev/null
PPG="$WORK/prefix/bin/project-path-gateway"
cat "$WORK/prefix/share/project-path-gateway/install-manifest"
mkdir -p "$WORK/p6"
"$PPG" init "$WORK/p6"
find "$WORK/p6" -type f | LC_ALL=C sort
cat "$WORK/p6/.tools/project-path-gateway/project-path-gateway.dirs.conf" "$WORK/p6/.tools/project-path-gateway/project-path-gateway.files.conf"
diff "$WORK/prefix/share/project-path-gateway/SKILL.md" "$WORK/p6/.agents/skills/project-path-gateway/SKILL.md" &&
	echo skill-same
(cd "$WORK/p6" && "$SH" -c '. ./.tools/project-path-gateway/project-path-gateway.sh
	project_path_gateway_init && project_path_gateway_verify &&
	project_path_gateway_dir PPG_TOOL_DIR && project_path_gateway_dir AGENT_SKILLS_DIR')
cp -R "$WORK/p6" "$WORK/p6-before"
"$PPG" init "$WORK/p6"
diff -r "$WORK/p6-before" "$WORK/p6" && echo rerun-same
```

기대 결과:

- 설치 목록 다섯 줄(`share/project-path-gateway/SKILL.md` 포함).
- 파일 다섯 개(표식, 디렉터리·파일 데이터 파일, 라이브러리, `.agents/skills/project-path-gateway/SKILL.md`), 출력 `생성:` 다섯 줄 + `초기화 완료`.
- 디렉터리 데이터 파일에 기본 항목 `PPG_TOOL_DIR=.tools/project-path-gateway`, `AGENT_SKILLS_DIR=.agents/skills`. 파일 데이터 파일은 주석뿐입니다(기능 007).
- `skill-same`, `project-path-gateway: 검증 통과 2건`, 두 경로의 절대경로 출력.
- 재실행은 `유지`·`유지`·`유지`·`교체`·`교체` 다섯 줄이고 `rerun-same`.

실패와 되돌리기(root가 아닌 사용자):

```sh
mkdir -p "$WORK/q6"; : >"$WORK/q6/.agents"
"$PPG" init "$WORK/q6"; echo "status=$?"; ls -A "$WORK/q6"
mkdir -p "$WORK/r6/.agents/skills"; chmod 555 "$WORK/r6/.agents/skills"
"$PPG" init "$WORK/r6"; echo "status=$?"; ls -A "$WORK/r6" "$WORK/r6/.agents"
chmod 755 "$WORK/r6/.agents/skills"
mv "$WORK/prefix/share/project-path-gateway/SKILL.md" "$WORK/skill-away"
mkdir -p "$WORK/s6"; "$PPG" init "$WORK/s6"; echo "status=$?"; ls -A "$WORK/s6"
mv "$WORK/skill-away" "$WORK/prefix/share/project-path-gateway/SKILL.md"
```

기대 결과:

- 첫째: stderr `디렉터리가 아닙니다: <WORK>/q6/.agents`, `status=2`, `.agents` 파일만 있고 `.tools` 없음.
- 둘째: stderr `파일을 쓰지 못했습니다: <WORK>/r6/.agents/skills/project-path-gateway`, `status=1`,
  이번 실행이 만든 `.tools`는 사라지고 원래 있던 `.agents/skills`는 그대로.
- 셋째: stderr `스킬 원본을 찾지 못했습니다: ...SKILL.md. 설치 스크립트를 다시 실행하세요`, `status=1`, `<WORK>/s6`은 빈 디렉터리.

스킬 문서 검토(SC-005): `share/SKILL.md`에 머리말 키 두 개(`name`, `description`), 공개 함수 여덟 개(기능 007)의 인자·반환 설명,
데이터 파일 두 개의 위치와 기본 항목, 경로 모양 규칙, 금지 항목, 예시 두 개가 있는지 읽어서 확인합니다. 버전·날짜·절대경로는 없어야 합니다.

## 13. 1.x 프로젝트 옮기기 (기능 007 US5, FR-030)

1.x 데이터 파일 하나를 쓰던 프로젝트를 README "1.x 프로젝트 옮기기" 절차대로 옮깁니다. 1.x 라이브러리는 기능 006 최종 커밋 `015739d`에서 가져옵니다.

```sh
"$SH" install.sh --prefix "$WORK/prefix" >/dev/null
PPG="$WORK/prefix/bin/project-path-gateway"
m="$WORK/m7"; t7="$m/.tools/project-path-gateway"
mkdir -p "$t7" "$m/config" "$m/src" && : >"$m/config/app.json" && : >"$m/Makefile"
git show 015739d:lib/project-path-gateway.sh >"$t7/project-path-gateway.sh"
printf '%s\n' '# marker' 'format=1' >"$t7/.project-path-gateway"
printf 'APP_CONFIG=config/app.json\nSOURCES_ROOT=src\nROOT_MAKEFILE=Makefile\n' >"$t7/project-path-gateway.conf"
cp "$t7/project-path-gateway.conf" "$WORK/legacy.orig"
g7() { (cd "$m" && "$SH" -c '. ./.tools/project-path-gateway/project-path-gateway.sh; project_path_gateway_init || exit 2; "$@"' _ "$@"); }
g7 project_path_gateway_get APP_CONFIG; echo "1x-get=$?"
"$PPG" init "$m"; echo "init=$?"
cmp "$WORK/legacy.orig" "$t7/project-path-gateway.conf" && echo 이전파일불변
mv "$t7/project-path-gateway.dirs.conf" "$WORK/dirs.away"
g7 true; echo "lib-init=$?"
mv "$WORK/dirs.away" "$t7/project-path-gateway.dirs.conf"
g7 project_path_gateway_get APP_CONFIG; echo "removed-get=$?"
g7 project_path_gateway_add_file APP_CONFIG config/app.json; echo "move-file=$?"
g7 project_path_gateway_add_dir SOURCES_ROOT src; echo "move-dir=$?"
g7 project_path_gateway_add_file ROOT_MAKEFILE Makefile; echo "makefile=$?"
g7 project_path_gateway_add_dir ROOT_DIR .; echo "root-dir=$?"
g7 eval 'ls "$(project_path_gateway_dir ROOT_DIR)/Makefile"'
g7 project_path_gateway_file APP_CONFIG
g7 project_path_gateway_verify; echo "verify=$?"
"$PPG" init "$m" >/dev/null; echo "rerun=$?"
rm "$t7/project-path-gateway.conf"
"$PPG" init "$m" >/dev/null; echo "after-rm=$?"
```

기대 결과:

- `<WORK>/m7/config/app.json`과 `1x-get=0`(1.x 라이브러리로 동작하는 프로젝트).
- `init` stdout `유지: .tools/project-path-gateway/.project-path-gateway`, `생성:` 디렉터리·파일 데이터 파일 두 줄,
  `교체: .tools/project-path-gateway/project-path-gateway.sh`, `생성: .agents/skills/project-path-gateway/SKILL.md`, `초기화 완료: <WORK>/m7`.
  stderr `project-path-gateway: init: 이전 형식 데이터 파일이 있습니다: .tools/project-path-gateway/project-path-gateway.conf. README의 "1.x 프로젝트 옮기기" 절차로 항목을 옮기세요`,
  `init=0`, `이전파일불변`.
- 새 데이터 파일 하나를 치운 상태의 런타임 초기화: stderr
  `project-path-gateway: project_path_gateway_init: 데이터 파일을 읽을 수 없습니다: <WORK>/m7/.tools/project-path-gateway/project-path-gateway.dirs.conf`와
  `project-path-gateway: project_path_gateway_init: 이전 형식 데이터 파일이 있습니다: <WORK>/m7/.tools/project-path-gateway/project-path-gateway.conf. README의 "1.x 프로젝트 옮기기" 절차로 항목을 옮기세요`,
  `lib-init=2`.
- 제거된 함수 호출은 셸의 명령 없음 오류(`/bin/sh`는 `command not found`, `dash`는 `not found`)와 `removed-get=127`.
- `move-file=0`, `move-dir=0`. `Makefile`은 파일 모양 위반(`makefile=2`)이므로 `ROOT_DIR=.`(`root-dir=0`)로 대신하고,
  `<WORK>/m7/./Makefile`이 출력됩니다(`ls` 결과. 조회 결과는 경로를 정규화하지 않으므로 `./`가 남습니다). 이어서 `<WORK>/m7/config/app.json`.
- `project-path-gateway: 검증 통과 5건`(기본 디렉터리 항목 두 개 + 옮긴 항목 세 개), `verify=0`.
- 이전 파일이 남아 있는 재실행은 같은 안내를 stderr에 다시 내고 `rerun=0`. 이전 파일을 지운 뒤에는 stderr 출력 없이 `after-rm=0`.

## 14. 찾기와 일괄 등록 (기능 008)

기능 008의 시스템 포트(`find`, `head`, `tr`, 표준 입력)와 찾기 → 일괄 등록 → 검증 흐름을 실제 파일 시스템에서 확인합니다.

### 14.1 시스템 포트 실제 동작

```sh
s="$WORK/s"
mkdir -p "$s/.git/hooks" "$s/bin" "$s/real" "$s/locked" "$s/a
b"
printf 'ls src\n' >"$s/a.sh"; printf 'ls src\n' >"$s/.git/hooks/pre-commit.sh"; printf 'ls src\n' >"$s/real/in.sh"
printf 'ls src\n' >"$s/locked/l.sh"; printf 'ls src\n' >"$s/a
b/x.sh"
printf '#!/usr/bin/env bash\nls src' >"$s/bin/run"; chmod 755 "$s/bin/run"
printf '#!/bin/sh\000\000x\nls src\n' >"$s/bin/nul"; chmod 755 "$s/bin/nul"
printf 'ls\n' >"$s/bin/noexec"
ln -s real "$s/linkdir"; ln -s a.sh "$s/link.sh"; mkfifo "$s/fifo"
chmod 000 "$s/locked"
"$SH" -c '
. "$1/lib/project-path-gateway.sh"
s=$2
project_path_gateway__sys_find_scripts "$s" | LC_ALL=C sort
printf "first=[%s]\n" "$(project_path_gateway__sys_read_first_line "$s/bin/run")"
printf "nul=[%s]\n" "$(project_path_gateway__sys_read_first_line "$s/bin/nul")"
project_path_gateway__sys_read_first_line "$s/none" || echo first-line-fail
project_path_gateway__sys_path_kinds "$s/real
$s/a.sh
$s/linkdir
$s/link.sh
$s/fifo
$s/none

$s/linkdir/in.sh"
printf "A=a\nB=b" | project_path_gateway__sys_read_stdin; echo
project_path_gateway__port_script_lines "$s"
' _ "$REPO" "$s"
chmod 755 "$s/locked"
```

기대 결과(`<S>`는 `$WORK/s`):

- 찾기 대상 네 줄 `<S>/a.sh`, `<S>/bin/nul`, `<S>/bin/run`, `<S>/real/in.sh`. `.git` 아래, 이름에 LF가 든 디렉터리 아래, 읽을 수 없는 디렉터리 아래,
  링크 디렉터리 안(`linkdir/in.sh`), 링크 파일(`link.sh`), 실행 권한 없는 확장자 없는 파일(`bin/noexec`)은 없습니다.
- `first=[#!/usr/bin/env bashx]`(끝 LF 없는 파일), `nul=[#!/bin/shxx]`(NUL 바이트 제거), `first-line-fail`.
- 종류 여덟 줄 `dir`, `file`, `dir`, `file`, `other`, `none`, `none`, `file`(링크는 최종 대상, 빈 줄은 `none`).
- 표준 입력 `A=a`, `B=bx`.
- 찾기 스트림: `F<TAB><S>/a.sh`, `L<TAB>ls src`, `F<TAB><S>/bin/run`, `L<TAB>#!/usr/bin/env bash`, `L<TAB>ls src`, `F<TAB><S>/real/in.sh`, `L<TAB>ls src`.
  `bin/nul`은 첫 줄이 `#!/bin/shx`라 셸 스크립트가 아닙니다.

### 14.2 찾기 → 일괄 등록 → 검증

```sh
root="$WORK/p"; t="$root/.tools/project-path-gateway"
mkdir -p "$t" "$root/src" "$root/config" "$root/scripts"
printf '# marker\nformat=1\n' >"$t/.project-path-gateway"
printf 'PPG_TOOL_DIR=.tools/project-path-gateway\n' >"$t/project-path-gateway.dirs.conf"
: >"$t/project-path-gateway.files.conf"
printf '{}\n' >"$root/config/app.json"; : >"$root/Makefile"
printf '%s\n' '#!/bin/sh' 'ROOT=$(cd "$(dirname "$0")/.." && pwd)' 'ls src' 'cat "$ROOT/config/app.json"' 'make -f Makefile' >"$root/scripts/build.sh"
: >"$WORK/stamp"; sleep 1
"$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" || exit 2
	project_path_gateway_scan >"$3"; echo "scan=$?"' _ "$REPO" "$root" "$WORK/paths.list"
find "$root" -newer "$WORK/stamp" | grep -q . || echo 파일시스템불변
cat "$WORK/paths.list"
"$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" || exit 2
	project_path_gateway_add_list "$3" && project_path_gateway_verify
	project_path_gateway_add_list - <"$3"; echo "stdin=$?"
	project_path_gateway_scan | sed -n "3p"' _ "$REPO" "$root" "$WORK/paths.list"
cat "$t/project-path-gateway.dirs.conf" "$t/project-path-gateway.files.conf"
```

기대 결과:

- `scan=0`, `파일시스템불변`.
- 찾기 결과: 머리 두 줄 뒤 `# 요약: 스크립트 1개, 새 후보 2, 이미 등록 0, 등록 불가 1, 확인 필요 0, 루트 참조 1`,
  새 후보 `CONFIG_APP_JSON=config/app.json`(위치 `scripts/build.sh:4: "$ROOT/config/app.json"`)와 `SRC=src`(위치 `scripts/build.sh:3: src`),
  `Makefile` 등록 불가 주석(파일 모양이 아님), 루트 참조 주석(위치 `scripts/build.sh:2: "$(dirname "$0")/.."`).
- `project-path-gateway: 일괄 등록: 디렉터리 1건, 파일 1건, 유지 0건`, `project-path-gateway: 검증 통과 3건`.
- 같은 목록을 표준 입력으로 다시 넘기면 `project-path-gateway: 일괄 등록: 디렉터리 0건, 파일 0건, 유지 2건`, `stdin=0`.
- 다시 찾으면 `# 요약: 스크립트 1개, 새 후보 0, 이미 등록 2, 등록 불가 1, 확인 필요 0, 루트 참조 1`.
- 데이터 파일 `PPG_TOOL_DIR=.tools/project-path-gateway`, `SRC=src`, `CONFIG_APP_JSON=config/app.json`.

### 14.3 목록 위반과 쓰기 실패

```sh
q="$WORK/q"; tq="$q/.tools/project-path-gateway"
mkdir -p "$tq" "$q/src"
printf '# marker\nformat=1\n' >"$tq/.project-path-gateway"
printf 'PPG_TOOL_DIR=.tools/project-path-gateway\n' >"$tq/project-path-gateway.dirs.conf"
: >"$tq/project-path-gateway.files.conf"; : >"$q/Makefile"
cp "$tq/project-path-gateway.dirs.conf" "$WORK/q-dirs"; cp "$tq/project-path-gateway.files.conf" "$WORK/q-files"
printf '%s\n' 'src=src' 'OUT=../out' 'A=a' 'A=b' 'PPG_TOOL_DIR=x' 'MAKEFILE=Makefile' >"$WORK/bad.list"
printf '%s\n' 'SRC=src' 'APP=config/app.json' >"$WORK/good.list"
g() { "$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" || exit 2; shift 2; "$@"' _ "$REPO" "$q" "$@"; }
same() { cmp -s "$WORK/q-dirs" "$tq/project-path-gateway.dirs.conf" && cmp -s "$WORK/q-files" "$tq/project-path-gateway.files.conf" && echo 두파일그대로; }
g project_path_gateway_add_list "$WORK/bad.list"; echo "bad=$?"; same
chmod 444 "$tq/project-path-gateway.files.conf"
g project_path_gateway_add_list "$WORK/good.list"; echo "readonly=$?"
chmod 644 "$tq/project-path-gateway.files.conf"; same
```

기대 결과:

- stderr에 줄 번호 순서로 위반 다섯 줄(`<WORK>/bad.list:1` 키 형식, `:2` `..` 세그먼트, `:4` 목록 안 중복 키(3번째 줄), `:5` 이미 다른 경로로 등록된 키
  (`project-path-gateway.dirs.conf: .tools/project-path-gateway`), `:6` 디렉터리 모양이지만 실제로는 일반 파일)과
  `project-path-gateway: project_path_gateway_add_list: 목록 위반 5건이 있어 아무것도 등록하지 않았습니다`, `bad=2`, `두파일그대로`.
- `project-path-gateway: project_path_gateway_add_list: 데이터 파일에 쓰기 권한이 없습니다: <WORK>/q/.tools/project-path-gateway/project-path-gateway.files.conf`,
  `readonly=2`, `두파일그대로`(디렉터리 데이터 파일도 쓰지 않음).

### 14.4 하나씩 등록한 결과와 바이트 비교

```sh
for v in lf nolf; do
	for side in list each; do
		r="$WORK/b.$v.$side"; tb="$r/.tools/project-path-gateway"
		mkdir -p "$tb"; printf '# marker\nformat=1\n' >"$tb/.project-path-gateway"
		if [ "$v" = lf ]; then printf 'A_DIR=a\n' >"$tb/project-path-gateway.dirs.conf"; printf 'B=b.txt\n' >"$tb/project-path-gateway.files.conf"
		else printf 'A_DIR=a' >"$tb/project-path-gateway.dirs.conf"; printf 'B=b.txt' >"$tb/project-path-gateway.files.conf"; fi
	done
	"$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" && printf "SRC=src\nAPP=config/app.json\nDOCS=docs\n" | project_path_gateway_add_list -' _ "$REPO" "$WORK/b.$v.list" >/dev/null
	"$SH" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" && project_path_gateway_add_dir SRC src && project_path_gateway_add_file APP config/app.json && project_path_gateway_add_dir DOCS docs' _ "$REPO" "$WORK/b.$v.each"
	for f in dirs files; do cmp "$WORK/b.$v.list/.tools/project-path-gateway/project-path-gateway.$f.conf" "$WORK/b.$v.each/.tools/project-path-gateway/project-path-gateway.$f.conf" && echo "same-$v-$f"; done
done
```

기대 결과: `same-lf-dirs`, `same-lf-files`, `same-nolf-dirs`, `same-nolf-files`(기능 008 FR-035).

### 14.5 이 저장소 찾기 결과의 두 셸 비교

저장소 사본에 도구 파일을 두고 찾기를 두 셸에서 실행해 결과가 바이트 단위로 같은지 봅니다. 이 절은 셸마다 나누지 않고 한 번 실행합니다.

```sh
mkdir -p "$WORK/repo" && git archive HEAD | tar -x -C "$WORK/repo"
t="$WORK/repo/.tools/project-path-gateway"; mkdir -p "$t"
printf '# marker\nformat=1\n' >"$t/.project-path-gateway"
printf 'PPG_TOOL_DIR=.tools/project-path-gateway\n' >"$t/project-path-gateway.dirs.conf"; : >"$t/project-path-gateway.files.conf"
for s in /bin/sh dash; do
	"$s" -c '. "$1/lib/project-path-gateway.sh"; project_path_gateway_init "$2" && project_path_gateway_scan' _ "$REPO" "$WORK/repo" >"$WORK/scan.${s##*/}"
done
cmp "$WORK/scan.sh" "$WORK/scan.dash" && echo 두셸같음
sed -n 3p "$WORK/scan.sh"
```

기대 결과: `두셸같음`과 요약 줄. 기록(2.1.0, 2026-10-23): `# 요약: 스크립트 46개, 새 후보 22, 이미 등록 1, 등록 불가 4, 확인 필요 3, 루트 참조 1`.
새 후보는 스크립트가 실제로 가리키는 디렉터리·파일(`bin`, `lib/project-path-gateway.sh`, `tests/harness/case.sh` 등)이고, 확인 필요 3건 가운데
`.agents/skills`·`.agents/skills/project-path-gateway`는 사본에 없는 실제 경로, `2`는 여러 줄 awk 프로그램 안의 `>&2/` 조각입니다.
등록 불가 `version`은 대소문자를 구분하지 않는 파일 시스템에서 `VERSION`과 같은 경로로 판정된 것입니다(README "찾기의 범위와 한계").
루트 참조에는 라이브러리 원본의 awk 코드 `".."`가 섞입니다(프로젝트에 설치된 라이브러리는 도구 파일이라 찾지 않음).

### 14.6 성능

quickstart(기능 008 `quickstart.md` 6절) 절차로 잽니다. 9절 절차에서 기준 커밋을 `d176cf0`(2.0.0)으로 바꿔 초기화+검증·조회·등록을 비교하고,
항목 200개 데이터에서 `KEY_200..399` 목록의 `add_list` 시간과 `add_file` 한 번 시간을, 스크립트 100개(합계 1만 줄)의 `project_path_gateway_scan`
시간을 두 셸에서 잽니다. 기대: 기존 동작 2.0.0의 110% 이내, 일괄 등록 `add_file`의 3배 이내, 찾기는 기록(30초를 넘으면 원인 보고).
측정값은 `specs/008-path-scan-register/perf.md`에 남깁니다(커밋 대상 아님).
