#!/usr/bin/env bash
# ==================== 系统识别 ====================

detect_os() {
    [[ -f /etc/os-release ]] || die "无法识别操作系统"

    . /etc/os-release

    case "${ID}" in
        debian|ubuntu)
            OS="debian"
            ;;
        alpine)
            OS="alpine"
            ;;
        *)
            die "暂不支持系统: ${ID}"
            ;;
    esac

    if [[ "$OS" == "alpine" ]]; then
        if [[ -x /sbin/openrc-run ]] ||
           command -v rc-service >/dev/null 2>&1; then
            INIT="openrc"
        else
            die "Alpine 未检测到 OpenRC"
        fi
    elif [[ "$(ps -p 1 -o comm= | tr -d ' ')" == "systemd" ]] &&
         command -v systemctl >/dev/null 2>&1; then
        INIT="systemd"
    else
        die "Debian / Ubuntu 未检测到 systemd"
    fi

    info "操作系统: ${PRETTY_NAME:-$ID}"
    info "服务管理: ${INIT}"
}

# ==================== 安装依赖 ====================

install_dependencies() {
    info "安装依赖..."

    if [[ "$OS" == "debian" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y curl unzip ca-certificates openssl
    else
        apk add --no-cache curl unzip ca-certificates openssl
    fi

    success "依赖安装完成"
}

# ==================== CPU 架构识别 ====================

detect_arch() {
    local machine
    machine="$(uname -m)"

    case "$machine" in
        x86_64|amd64)
            ARCH="64"
            ;;
        aarch64|arm64)
            ARCH="arm64-v8a"
            ;;
        armv7l|armv7)
            ARCH="arm32-v7a"
            ;;
        *)
            die "不支持的 CPU 架构: $machine"
            ;;
    esac

    info "CPU 架构: ${machine}"
}
