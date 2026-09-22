#!/bin/sh
# lint-fixture: kind=bin expect=D-6
# 인프라에 정의한 입력 포트가 포트 목록에 없다(애플리케이션은 부르지 않는다).

# === 계층: 도메인 ===

ppg__domain_name() {
	printf 'x\n'
}

# === 계층: 애플리케이션 ===

# 입력 포트: ppg__port_read
# 출력 포트: ppg__out_done

ppg__app_run() {
	ppg_app_value=$(ppg__port_read "$1")
	ppg__out_done "$(ppg__domain_name) $ppg_app_value"
}

# === 계층: 인프라 ===

ppg__port_read() {
	ppg__sys_read "$1"
}

ppg__port_unused() {
	ppg__sys_read /dev/null
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
