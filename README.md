# project-path-gateway

프로젝트에서 쓰는 경로를 데이터 파일 한 곳에 정의하고, 셸 스크립트와 Git 훅이 키 이름으로 프로젝트 루트 기준
절대경로를 얻게 하는 POSIX `sh` 라이브러리입니다.

- 경로를 옮기거나 지울 때 데이터 파일 한 곳만 고치면 모든 스크립트가 새 경로를 씁니다.
- 등록한 경로가 실제로 있는지 pre-commit 훅에서 커밋 전에 확인할 수 있습니다.
- 개발자 PC에는 전역 프로그램을 한 번 설치하고, 프로젝트에는 라이브러리 파일을 함께 커밋합니다.
  저장소를 clone한 다른 환경은 전역 프로그램 없이 조회·검증을 사용합니다.

## 설치

저장소를 받고, 설치 스크립트를 실행하고, 프로젝트를 초기화하는 세 단계입니다.

```sh
git clone <저장소 URL> project-path-gateway
sh project-path-gateway/install.sh
project-path-gateway init /path/to/my-project
```

- 기본 설치 위치는 `~/.local`입니다. 실행 파일은 `~/.local/bin/project-path-gateway`, 라이브러리 원본은
  `~/.local/share/project-path-gateway/`에 설치됩니다. 관리자 권한은 필요하지 않습니다.
- 다른 위치에 설치하려면 `sh install.sh --prefix DIR`을 쓰거나 환경 변수 `PREFIX`를 지정합니다. `--prefix`가 우선합니다.
- `<PREFIX>/bin`이 `PATH`에 없으면 설치는 성공하고 추가할 `export PATH=...` 줄을 안내합니다. 셸 설정 파일은 수정하지 않습니다.
- 설치 스크립트를 다시 실행하면 현재 저장소 버전으로 교체합니다.

제거:

```sh
sh project-path-gateway/uninstall.sh [--prefix DIR]
```

제거 스크립트는 설치 목록(`<PREFIX>/share/project-path-gateway/install-manifest`)에 적힌 파일만 지웁니다.
이미 초기화한 프로젝트 안의 파일은 건드리지 않으므로, 제거 후에도 프로젝트의 조회·검증은 계속 동작합니다.

## 프로젝트 초기화

```sh
project-path-gateway init [TARGET_DIR]
```

`TARGET_DIR`(생략하면 현재 작업 디렉터리)이 프로젝트 루트가 되고, 그 아래 도구 디렉터리에 파일 세 개를 만듭니다.

```text
<루트>/
└── .tool/
    └── project-path-gateway/
        ├── .project-path-gateway        # 루트 표식 파일
        ├── project-path-gateway.conf    # 데이터 파일
        └── project-path-gateway.sh      # 라이브러리
```

| 파일 | 없을 때 | 있을 때 |
|---|---|---|
| 루트 표식 파일 | 생성 | 유지(내용·수정 시각 그대로) |
| 데이터 파일 | 생성(주석만 있고 항목 0개) | 유지(내용·수정 시각 그대로) |
| 라이브러리 | 생성 | 전역 프로그램에 포함된 버전으로 교체 |

- 파일마다 `생성`, `유지`, `교체` 중 무엇을 했는지 출력하고, 마지막 줄에 `초기화 완료: <루트 물리 경로>`를 출력합니다.
- 어떤 파일에도 루트 절대경로, 사용자 이름, 날짜를 기록하지 않습니다. clone 위치가 달라도 그대로 동작합니다.
- `.tool/` 안의 다른 도구 항목은 건드리지 않습니다. Git 저장소인지는 확인하지 않습니다.
- 대상이 디렉터리가 아니거나 `.tool`·도구 디렉터리·세 파일 중 형태가 맞지 않는 것이 있으면 아무 파일도 만들지 않고
  반환 2로 끝납니다. 쓰기 중 실패하면 반환 1이며, 처리 중이던 파일은 이전 상태로 남습니다.
- **`.tool/project-path-gateway/`는 반드시 프로젝트와 함께 커밋하세요.** `.gitignore`에 넣으면 clone한 환경에서
  라이브러리와 데이터 파일을 찾을 수 없습니다.

## 루트 표식 파일과 루트 탐색 규칙

런타임 초기화(`project_path_gateway_init`)는 탐색 시작 디렉터리에서 `/`까지 상위로 올라가며,
`<디렉터리>/.tool/project-path-gateway/.project-path-gateway`가 일반 파일로 있는 **가장 가까운** 디렉터리를 루트로 삼습니다.

- 탐색 시작 디렉터리는 인자가 없으면 현재 작업 디렉터리, 있으면 그 인자(절대경로)입니다.
- 시작 디렉터리와 루트는 심볼릭 링크를 해소한 물리 경로로 계산합니다.
- 루트 표식 파일은 존재만 확인하고 내용을 읽지 않습니다. 같은 이름의 디렉터리는 표식으로 인정하지 않습니다.
- 계산한 루트는 호출 셸 변수 `PROJECT_PATH_GATEWAY_ROOT`에만 보관합니다. 파일에 쓰거나 `export`하지 않으며,
  스크립트 실행이 끝나면 사라집니다. 조회·검증은 루트를 다시 탐색하지 않습니다.
- 라이브러리는 Git을 호출하지 않습니다.

## 데이터 파일 규칙

`<루트>/.tool/project-path-gateway/project-path-gateway.conf`

```text
# 주석
APP_CONFIG=config/app.json
BUILD_SCRIPT=scripts/build.sh
```

- 한 줄에 `KEY=경로` 하나. 첫 번째 `=`가 구분자이고 그 뒤 전체가 경로입니다. 공백은 어디에서도 제거하지 않습니다.
- 빈 줄(문자가 하나도 없는 줄)과 첫 문자가 `#`인 줄은 무시합니다. 공백만 있는 줄, 공백 뒤 `#`인 줄은 오류입니다.
- 키: 대문자로 시작하고 대문자·숫자·`_`만 사용하며, 파일 안에서 중복될 수 없습니다.
- 경로: **루트 기준** 상대경로입니다(도구 디렉터리 기준이 아님). 비어 있으면 안 되고, `/`로 시작하거나 `..` 세그먼트를
  쓰거나 CR 문자를 포함할 수 없습니다. 공백·한글·`=`·`.` 세그먼트·빈 세그먼트·끝 `/`는 허용합니다.
- 파일은 UTF-8, LF 줄 끝으로 읽습니다. 마지막 줄에 개행이 없어도 됩니다. CRLF 파일은 오류로 보고하며 원인에 안내가 붙습니다.
- 위반 줄이 하나라도 있으면 파일 전체가 무효이며, 위반 줄 전체를 파일 순서대로 보고합니다.
- 조회와 검증은 호출할 때마다 데이터 파일을 다시 읽고 다시 검증합니다.
- 파일을 직접 편집하는 대신 `project_path_gateway_add`, `project_path_gateway_update`로 항목을 넣거나 경로를 바꿀 수 있습니다.
  두 함수는 규칙을 확인한 뒤에만 파일을 바꿉니다(아래 "경로 항목 등록·갱신").

## 런타임 초기화 방법

라이브러리를 불러온(source) 뒤 스크립트마다 한 번 초기화합니다.

```sh
. ./.tool/project-path-gateway/project-path-gateway.sh
project_path_gateway_init                      # 인자 생략: 현재 작업 디렉터리에서 탐색 (프로젝트 안에서 실행할 때)
project_path_gateway_init /abs/path/in/project # 경로 전달: 그 디렉터리에서 탐색 (프로젝트 밖에서 실행할 때)
```

초기화에 성공한 뒤 작업 디렉터리를 바꿔도 루트는 바뀌지 않습니다. 다시 호출하면 루트를 새로 계산합니다.
실패하면 이전 루트를 지우고 미초기화 상태가 됩니다.

## 공개 기능

| 함수 | 설명 | 반환값 |
|---|---|---|
| `project_path_gateway_init [START_DIR]` | 루트를 찾고 데이터 파일을 검증해 루트를 보관합니다. stdout 출력 없음 | 0 성공, 2 실패 |
| `project_path_gateway_get KEY` | 등록된 경로를 루트와 결합한 절대경로 한 줄을 출력합니다. 경로 존재는 확인하지 않습니다 | 0 성공, 2 실패 |
| `project_path_gateway_verify [REPORT_FILE]` | 모든 항목이 존재하고(링크는 최종 대상 존재) 최종 물리 경로가 루트 안인지 확인합니다. `REPORT_FILE`을 주면 같은 결과를 그 파일에도 저장합니다 | 0 통과, 1 검증 실패, 2 오류 |
| `project_path_gateway_add KEY PATH` | 새 항목 `KEY=PATH`를 데이터 파일 끝에 등록합니다. 키가 이미 있으면 경로가 같아도 오류입니다. 출력 없음 | 0 성공, 2 실패 |
| `project_path_gateway_update KEY PATH` | 등록된 키의 경로를 바꿉니다. 키가 없으면 오류이며 새로 등록하지 않습니다. 출력 없음 | 0 성공, 2 실패 |

| 반환값 | 의미 |
|---|---|
| 0 | 성공 |
| 1 | `project_path_gateway_verify` 검증 실패 |
| 2 | 인자 오류, 미초기화, 루트 오류, 데이터 파일 오류, 미등록 키, 이미 등록된 키, 리포트 파일·데이터 파일 쓰기 실패 |

- 검증은 첫 실패에서 멈추지 않고 모든 항목을 확인합니다. 끊어진 링크, 순환 링크, 권한 때문에 확인할 수 없는 경로는 누락입니다.
- `REPORT_FILE` 없이 호출한 검증은 파일 시스템을 바꾸지 않습니다. 검증 대상은 작업 트리이며 스테이징 여부는 보지 않습니다.
- 인자는 0개 또는 1개입니다. 이전 버전에서 인자를 주면 오류였지만, 지금은 인자 1개를 리포트 파일 경로로 씁니다.

### 검증 리포트 파일

`project_path_gateway_verify REPORT_FILE`은 터미널에 출력한 검증 결과 줄을 그대로 `REPORT_FILE`에 저장합니다.

- 리포트 내용: 실패 항목 줄(누락, 루트 밖)을 데이터 파일 순서대로 적고, 마지막 줄에 `검증 통과 <n>건` 또는 `검증 실패 <n>건`을
  적습니다. 형식은 아래 "출력 형식"의 해당 줄과 같습니다. 통과해도 요약 한 줄짜리 리포트를 남깁니다.
- 상대경로는 호출한 시점의 작업 디렉터리 기준입니다. 상위 디렉터리는 만들지 않습니다.
- 기존 파일은 새 리포트로 한 번에 바뀝니다. 같은 디렉터리에 임시 파일 `.ppg-report.<PID>.<이름>`을 쓴 뒤 옮기므로
  리포트 위치에 반쯤 쓴 파일이 보이지 않습니다. 리포트 위치가 파일을 가리키는 링크이면 링크 자리가 리포트 파일로 바뀝니다.
- 리포트를 쓰지 못하면(상위 디렉터리 없음, 권한 없음, 디렉터리나 디렉터리 링크, `dir/`처럼 이름이 없는 경로) 검증 출력 뒤에
  `리포트 파일을 쓸 수 없습니다: <REPORT_FILE>`을 출력하고 반환 2입니다.
- 미초기화, 데이터 파일 오류처럼 항목을 검사하지 못하면 리포트를 만들거나 바꾸지 않습니다.
- 리포트를 지정하면 실패 항목 줄은 검사가 끝난 뒤 한꺼번에 출력됩니다. 내용과 순서는 리포트를 지정하지 않았을 때와 같습니다.
- 리포트 쓰기 도중 신호로 중단되면 임시 파일 `.ppg-report.<PID>.<이름>`이 남을 수 있습니다.
- 한 셸에서 백그라운드 작업으로 같은 `REPORT_FILE`에 동시에 쓰지 마세요. 임시 파일 이름이 같아집니다. 서로 다른 셸 프로세스의
  동시 실행은 둘 중 한 실행의 완전한 리포트를 남깁니다.
- 루트가 `/`이면 조회 결과는 `/<경로>`이고 모든 경로가 루트 안으로 판정됩니다.

### 경로 항목 등록·갱신

`project_path_gateway_add KEY PATH`는 새 항목을 등록하고, `project_path_gateway_update KEY PATH`는 등록된 키의 경로를 바꿉니다.
두 함수 모두 런타임 초기화 뒤에 쓰며, 성공하면 아무것도 출력하지 않고 반환 0입니다.

- 확인 순서: 인자 개수(2개) → 초기화 여부 → 키 규칙 → 경로 규칙(비어 있지 않음, `/`로 시작하지 않음, `..` 세그먼트 없음,
  CR·LF 없음) → 데이터 파일 검사(조회와 같은 오류 보고) → 키 존재 여부. 먼저 걸린 조건 하나만 보고하고 반환 2입니다.
- 등록은 같은 키가 있으면 `이미 등록된 키입니다: <KEY>`, 갱신은 키가 없으면 `등록되지 않은 키입니다: <KEY>`로 실패합니다.
  주석 줄(`# KEY=...`)은 항목이 아니므로 등록을 막지 않습니다.
- 등록은 파일 끝에 `KEY=PATH` 한 줄을 더합니다. 마지막 줄에 개행이 없으면 개행을 먼저 붙입니다. 갱신은 그 키의 줄 내용만 바꾸고
  다른 줄·주석·빈 줄·줄 순서·파일 끝 개행 여부는 그대로 둡니다. 갱신할 경로가 지금 경로와 같으면 파일을 쓰지 않고 반환 0입니다.
- 경로가 실제로 있는지는 확인하지 않습니다. 없는 경로도 등록되며, `project_path_gateway_verify`가 누락으로 보고합니다.
- 파일은 도구 디렉터리의 임시 파일 `.ppg-tmp.<PID>.project-path-gateway.conf`에 원본 접근 권한을 복사해 새 내용을 쓴 뒤 한 번에
  바꿉니다. 데이터 파일 위치에는 이전 내용이나 새 내용만 보입니다. 접근 권한(모드)은 유지되고 수정 시각은 갱신됩니다.
- 데이터 파일이 심볼릭 링크이거나 쓰기 권한이 없으면(도구 디렉터리는 쓸 수 있어도) 파일을 바꾸지 않고 반환 2입니다.
  임시 파일 쓰기나 교체에 실패하면 `데이터 파일을 쓸 수 없습니다: <데이터 파일>`을 출력하고 임시 파일을 지웁니다.
- 한계: 쓰기 중 신호로 중단되면 임시 파일 하나가 남을 수 있습니다. 소유자는 보존하지 않으며, 데이터 파일이 하드 링크이면
  교체 뒤 다른 이름과의 연결이 끊깁니다. 서로 다른 프로세스가 동시에 등록·갱신하면 파일은 깨지지 않지만 한쪽 변경이 빠질 수 있고,
  같은 셸의 백그라운드 작업끼리 동시에 호출하는 경우는 보장하지 않습니다(잠금 없음).
- 이미 초기화한 프로젝트의 라이브러리가 0.2.0보다 오래되었으면 두 함수가 없습니다. `project-path-gateway init <루트>`를 다시 실행해
  라이브러리를 교체하세요(데이터 파일은 유지됩니다).

## 출력 형식

| 구분 | 형식 | 출력 |
|---|---|---|
| 초기화·인자 오류 | `project-path-gateway: <기능 이름>: <원인>` | stderr |
| 데이터 파일 오류 | `project-path-gateway: <데이터 파일 절대경로>:<줄 번호>: <원인>` | stderr |
| 누락 | `project-path-gateway: 누락: <KEY>=<경로>` | stderr |
| 루트 밖 | `project-path-gateway: 루트 밖: <KEY>=<경로> -> <최종 물리 경로>` | stderr |
| 검증 실패 요약 | `project-path-gateway: 검증 실패 <n>건` | stderr 마지막 줄 |
| 검증 성공 요약 | `project-path-gateway: 검증 통과 <n>건` | stdout |
| 리포트 파일 | 위 누락·루트 밖·검증 요약 줄과 같은 내용 | `REPORT_FILE` |

## 제약

- POSIX `sh`로 작성했으며 macOS 기본 `/bin/sh`와 Linux `dash`에서 같은 결과를 냅니다. 실행에 필요한 도구는 두 환경의
  기본 유틸리티와 `readlink`뿐입니다. Windows 네이티브 셸은 지원하지 않습니다.
- 라이브러리는 호출 셸 안에서 실행되지만 호출 셸을 종료시키지 않고, 작업 디렉터리·셸 옵션·trap·`IFS`·호출자 변수를
  바꾸지 않습니다. 만드는 이름은 함수 `project_path_gateway_*`와 변수 `PROJECT_PATH_GATEWAY_ROOT`뿐입니다.
- 호출자가 `set -e`, `set -u`, `set -f`를 켜거나 `IFS`를 바꿔도 결과가 같습니다. 단, `set -e` 상태에서 공개 함수를
  조건 없이 호출해 실패하면 호출자의 `set -e` 규칙에 따라 스크립트가 끝납니다.
- 라이브러리를 이미 초기화된 셸에서 다시 불러와도 보관된 루트는 유지됩니다.
- 환경 변수로 경로를 덮어쓰는 기능, 데이터 파일 이름·위치 변경, 훅 자동 설치는 제공하지 않습니다.
  훅 등록(`.git/hooks/pre-commit` 또는 `core.hooksPath`)은 프로젝트가 담당합니다.

## 사용 예

아래 예는 데이터 파일에 `APP_CONFIG=config/app.json`이 등록된 프로젝트를 기준으로 합니다.

### 프로젝트 안 셸 스크립트

프로젝트 안 `scripts/show-config.sh`에 두고 프로젝트 안에서 실행합니다. 라이브러리는 스크립트 자기 위치(`$0`의
디렉터리) 기준으로 불러오고, 런타임 초기화는 인자 없이 합니다.

<!-- example: in-project -->
```sh
#!/bin/sh
# scripts/show-config.sh
set -eu
script_dir=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
. "$script_dir/../.tool/project-path-gateway/project-path-gateway.sh"

project_path_gateway_init
app_config=$(project_path_gateway_get APP_CONFIG)
printf '설정 파일: %s\n' "$app_config"
```

```sh
cd /path/to/my-project && sh scripts/show-config.sh
```

### 프로젝트 밖에서 실행되는 스크립트

프로젝트 밖에 있는 스크립트는 프로젝트 안의 절대경로를 인자로 받아 라이브러리를 불러오고 초기화합니다.

<!-- example: outside-project -->
```sh
#!/bin/sh
# 사용법: sh deploy.sh /path/to/my-project
set -eu
project_dir=${1:?프로젝트 절대경로를 인자로 주세요}
. "$project_dir/.tool/project-path-gateway/project-path-gateway.sh"

project_path_gateway_init "$project_dir"
project_path_gateway_get APP_CONFIG
```

### pre-commit 훅

Git은 훅을 실행하기 전에 작업 디렉터리를 작업 트리 루트로 옮깁니다. 그래서 훅은 루트 기준 상대경로로 라이브러리를
불러오고 인자 없이 초기화합니다. 등록 경로가 누락되었거나 루트 밖을 가리키면 검증이 반환 1로 끝나고 커밋이 중단됩니다.

<!-- example: pre-commit -->
```sh
#!/bin/sh
# .git/hooks/pre-commit (실행 권한 필요: chmod +x .git/hooks/pre-commit)
set -eu
. ./.tool/project-path-gateway/project-path-gateway.sh
project_path_gateway_init
project_path_gateway_verify
```

### CI에서 검증 리포트 남기기

저장소 루트에서 실행해 누락 경로 목록을 `path-report.txt`로 남깁니다. 검증에 실패하면 스크립트는 반환 1로 끝나고,
리포트 파일은 산출물로 수집할 수 있습니다.

<!-- example: ci-report -->
```sh
#!/bin/sh
# scripts/check-paths.sh (CI에서 저장소 루트를 작업 디렉터리로 실행)
set -eu
. ./.tool/project-path-gateway/project-path-gateway.sh
project_path_gateway_init
project_path_gateway_verify path-report.txt
```

### 경로 등록 스크립트

저장소 루트에서 실행해 필요한 경로를 등록하고, 이미 있는 키는 경로를 맞춥니다. 두 함수는 실패를 모두 반환 2로 알리므로
먼저 조회로 등록 여부를 확인해 갱신과 등록을 나눕니다.

<!-- example: register-paths -->
```sh
#!/bin/sh
# scripts/register-paths.sh (저장소 루트를 작업 디렉터리로 실행)
set -eu
. ./.tool/project-path-gateway/project-path-gateway.sh
project_path_gateway_init

register_path() {
	if project_path_gateway_get "$1" >/dev/null 2>&1; then
		project_path_gateway_update "$1" "$2"
	else
		project_path_gateway_add "$1" "$2"
	fi
}

register_path APP_CONFIG config/app.json
register_path DOCS docs
```

## 개발

```sh
sh scripts/lint.sh                # ShellCheck, 금지 단어, 범위 괄호식, 버전 일치, 계층 규칙
sh tests/run.sh                   # /bin/sh와 (있으면) dash에서 전체 사례
sh tests/run.sh --shell dash lib-get
sh tests/run.sh --shuffle 7       # 섞은 순서로 실행
```

테스트 사례는 `tests/cases/` 아래 `.cases` 파일에 있고, 실행기 인자의 필터는 사례 식별자(`<사례 파일 경로>:<이름>`)의
부분 문자열입니다. 테스트는 실제 파일 시스템을 바꾸지 않습니다. 실제 환경에서만 확인할 수 있는 동작은
`tests/manual-checks.md`의 절차로 확인합니다.
