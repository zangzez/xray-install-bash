#!/usr/bin/env bash
# ==================== 输出函数 ====================

info() {
    echo -e "\033[36m[INFO]\033[0m $*"
}

success() {
    echo -e "\033[32m[ OK ]\033[0m $*"
}

warn() {
    echo -e "\033[33m[WARN]\033[0m $*"
}

error() {
    echo -e "\033[31m[FAIL]\033[0m $*" >&2
}

die() {
    error "$*"
    exit 1
}

# ==================== 前置检查 ====================

check_prerequisites() {
    [[ "${EUID}" -eq 0 ]] || die "请使用 root 用户执行"

    [[ "$XRAY_PORT" =~ ^[0-9]+$ ]] &&
        (( XRAY_PORT >= 1 && XRAY_PORT <= 65535 )) ||
        die "端口不合法"

    [[ "$XRAY_SNI" =~ ^[a-zA-Z0-9.-]+$ ]] ||
        die "SNI 格式不合法"
}
