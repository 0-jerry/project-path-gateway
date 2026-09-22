#!/bin/sh
# lint-fixture: kind=bin expect=D-2
# 애플리케이션이 포트 목록에 없는 포트를 부른다. 목록 밖 포트 정의(D-6)도 함께 보고되는 것은 같은 위반의 두 면이다.

# === 계층: 도메인 ===

ppg__domain_name() {
	printf 'x\n'
}

# === 계층: 애플리케이션 ===

# 입력 포트: ppg__port_read
# 출력 포트: ppg__out_done

ppg__app_run() {
	ppg_app_value=$(ppg__port_read "$1")
	ppg__port_extra
	ppg__out_done "$(ppg__domain_name) $ppg_app_value"
}

# === 계층: 인프라 ===

ppg__port_read() {
	ppg__sys_read "$1"
}

ppg__port_extra() {
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
