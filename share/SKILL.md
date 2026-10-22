---
name: project-path-gateway
description: Look up project paths by key with the project-path-gateway shell library instead of hardcoding relative paths.
---

# project-path-gateway 사용법

## 개요

이 프로젝트는 자주 쓰는 경로를 데이터 파일 두 곳에 `KEY=경로` 형식으로 정의한다. 디렉터리는
`.tools/project-path-gateway/project-path-gateway.dirs.conf`, 파일은 `.tools/project-path-gateway/project-path-gateway.files.conf`에 적는다.
스크립트는 경로를 직접 적지 않고 종류에 맞는 함수로 키를 조회한다. 조회 결과는 프로젝트 루트 기준 절대경로이므로,
어느 디렉터리에서 실행해도 같은 값을 얻는다.

라이브러리는 POSIX `sh` 한 파일이며 프로젝트 안 `.tools/project-path-gateway/project-path-gateway.sh`에 있다.

## 언제 쓰는가

- 프로젝트 안 셸 스크립트가 파일·디렉터리 경로를 다룰 때.
- 여러 스크립트가 같은 디렉터리나 파일을 가리킬 때. 경로가 바뀌면 데이터 파일 한 줄만 고친다.
- 새 경로를 쓰기 시작할 때. 먼저 종류에 맞게 키로 등록하고 그 키를 쓴다.

경로를 문자열로 적거나 `cd ../..`로 루트를 찾는 코드는 쓰지 않는다.

## 불러오기와 초기화

```sh
. "<프로젝트 루트>/.tools/project-path-gateway/project-path-gateway.sh"
project_path_gateway_init                 # 현재 작업 디렉터리에서 위로 루트를 찾는다
project_path_gateway_init "$some_dir"     # 시작 디렉터리를 지정한다
```

`project_path_gateway_init`은 루트 표식 파일(`.tools/project-path-gateway/.project-path-gateway`)을 상위로 올라가며
찾아 호출 셸 변수 `PROJECT_PATH_GATEWAY_ROOT`에 루트 절대경로를 넣는다. 다른 공개 함수는 초기화 뒤에만 쓸 수 있다.
라이브러리는 호출 셸의 작업 디렉터리, `set` 옵션, `IFS`, trap을 바꾸지 않고 셸을 끝내지도 않는다.

## 공개 함수

| 함수 | 인자 | stdout | 반환 |
|---|---|---|---|
| `project_path_gateway_init` | `[START_DIR]` (0개 또는 1개) | 없음 | 0 성공 / 2 인자 오류·루트 없음·데이터 파일 오류 |
| `project_path_gateway_verify` | `[REPORT_FILE]` | `project-path-gateway: 검증 통과 N건` | 0 통과 / 1 검증 실패 / 2 인자 오류·미초기화·데이터 파일 오류 |
| `project_path_gateway_dir` | `KEY` | 디렉터리 절대경로 한 줄 | 0 성공 / 2 인자 오류·미초기화·미등록 키·파일 키·데이터 파일 오류 |
| `project_path_gateway_file` | `KEY` | 파일 절대경로 한 줄 | 0 성공 / 2 인자 오류·미초기화·미등록 키·디렉터리 키·데이터 파일 오류 |
| `project_path_gateway_add_dir` | `KEY PATH` | 없음 | 0 등록 / 2 인자 오류·미초기화·키 중복·키·경로·종류 규칙 위반 |
| `project_path_gateway_add_file` | `KEY PATH` | 없음 | 0 등록 / 2 인자 오류·미초기화·키 중복·키·경로·종류 규칙 위반 |
| `project_path_gateway_update_dir` | `KEY PATH` | 없음 | 0 갱신 / 2 인자 오류·미초기화·키 없음·파일 키·경로·종류 규칙 위반 |
| `project_path_gateway_update_file` | `KEY PATH` | 없음 | 0 갱신 / 2 인자 오류·미초기화·키 없음·디렉터리 키·경로·종류 규칙 위반 |
| `project_path_gateway_add_list` | `LIST` (목록 파일, `-`이면 표준 입력) | `project-path-gateway: 일괄 등록: 디렉터리 D건, 파일 F건, 유지 K건` | 0 등록 / 2 인자 오류·미초기화·목록 읽기 불가·목록 위반·쓰기 실패 |

- 오류는 모두 stderr에 `project-path-gateway: <함수 이름>: <원인>` 한 줄로 나온다.
- 디렉터리 키를 `project_path_gateway_file`로, 파일 키를 `project_path_gateway_dir`로 조회하면 종류가 다르다는 오류(반환 2)다.
- `project_path_gateway_verify`는 등록된 모든 경로가 실제로 있고 루트 안이며, 디렉터리 항목은 디렉터리, 파일 항목은
  일반 파일인지 확인한다. 누락·루트 밖·종류 불일치 항목은 stderr에 한 줄씩 적는다. `REPORT_FILE`을 주면 결과를 그 파일에도 쓴다.
- 반환값을 확인하고 쓴다. `set -e` 스크립트에서는 조건문 안에서 부른다.

## 데이터 파일

- 디렉터리 데이터 파일: `<루트>/.tools/project-path-gateway/project-path-gateway.dirs.conf`
- 파일 데이터 파일: `<루트>/.tools/project-path-gateway/project-path-gateway.files.conf`
- 한 줄에 `KEY=경로` 하나. 빈 줄과 `#`으로 시작하는 줄은 무시한다. 디렉터리 데이터 파일을 먼저 읽는다.
- 초기화가 디렉터리 데이터 파일에 넣는 기본 항목: `PPG_TOOL_DIR=.tools/project-path-gateway`, `AGENT_SKILLS_DIR=.agents/skills`.
- 같은 키를 두 번 쓸 수 없다. 두 파일을 합쳐서 유일해야 한다.

## 키·경로 규칙

- 키: 대문자로 시작하고 대문자·숫자·`_`만 쓴다. 예: `SOURCES_ROOT`, `BUILD_SCRIPT`.
- 경로: 프로젝트 루트 기준 상대경로다. `/`로 시작할 수 없고 `..` 세그먼트를 쓸 수 없다.
  `=` 앞뒤 공백은 값의 일부이므로 붙여 쓴다.
- 종류: 마지막 이름(끝 `/`는 뗀다)에 확장자가 있거나(`build.sh`, `archive.tar.gz`) `.`으로 시작하면(`.env`, `.github`) 파일 모양이다.
  그 밖(`src`, `.github/workflows`, `.`)은 디렉터리 모양이다. 디렉터리 항목은 디렉터리 모양, 파일 항목은 파일 모양이고 `/`로 끝나지 않아야 한다.
- `Makefile`처럼 확장자 없는 파일은 파일 항목으로 등록할 수 없다. 그 파일이 있는 디렉터리를 디렉터리 항목으로 등록해 쓴다.

## 하지 말 것

- 경로를 스크립트에 직접 적기. 종류에 맞는 함수로 키를 조회한다.
- 데이터 파일을 직접 파싱하거나 편집하기. 등록은 `project_path_gateway_add_dir`·`project_path_gateway_add_file`,
  갱신은 `project_path_gateway_update_dir`·`project_path_gateway_update_file`을 쓴다.
- `.tools/project-path-gateway/` 안의 표식 파일과 라이브러리 파일을 손대기. 라이브러리는 전역 프로그램 `init`이 교체한다.
- 절대경로나 기계별 값을 데이터 파일에 적어 저장소에 커밋하기.

## 예시

스크립트에서 키를 조회해 쓴다.

```sh
#!/bin/sh
set -eu
. "$(dirname "$0")/../.tools/project-path-gateway/project-path-gateway.sh"
if ! project_path_gateway_init; then
	echo '프로젝트 루트를 찾지 못했습니다' >&2
	exit 1
fi
if ! sources=$(project_path_gateway_dir SOURCES_ROOT); then
	exit 1
fi
if ! build_script=$(project_path_gateway_file BUILD_SCRIPT); then
	exit 1
fi
ls "$sources"
sh "$build_script"
```

새 경로를 등록하고 검증한다.

```sh
. .tools/project-path-gateway/project-path-gateway.sh
project_path_gateway_init
project_path_gateway_add_dir REPORT_DIR build/reports         # 이미 있으면 update_dir를 쓴다
project_path_gateway_add_file REPORT_INDEX build/index.html   # 이미 있으면 update_file을 쓴다
project_path_gateway_verify
```
