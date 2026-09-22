#!/bin/sh
# lint-fixture: kind=bin expect=D-6
# 출력 포트를 인프라 구획에 정의한다.

# === 계층: 도메인 ===

ppg__domain_name() {
	printf 'x\n'
}

# === 계층: 애플리케이션 ===

# 입력 포트: ppg__port_read
# 출력 포트: ppg__out_done ppg__out_extra

ppg__app_run() {
	ppg_app_value=$(ppg__port_read "$1")
	ppg__out_done "$(ppg__domain_name) $ppg_app_value"
}

# === 계층: 인프라 ===

ppg__port_read() {
	ppg__sys_read "$1"
}

ppg__out_extra() {
	printf 'extra\n'
}

ppg__sys_read() {
	cat -- "$1"
}

# === 계층: 인터페이스 ===

ppg__out_done() {
	printf 'done: %s\n' "$1"
}

main() {
	ppg__app_run "$@"
}
