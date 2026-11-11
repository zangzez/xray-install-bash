#!/usr/bin/env bash
#
# Xray VLESS + REALITY + Vision 一键部署
# 支持 Debian / Ubuntu / Alpine
# 支持 amd64 / arm64 / arm32
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#
# 自定义:
#   XRAY_PORT=8443 XRAY_SNI=www.microsoft.com ./install.sh

set -Eeuo pipefail

# ==================== 基础配置 ====================

XRAY_PORT="${XRAY_PORT:-443}"
XRAY_SNI="${XRAY_SNI:-www.microsoft.com}"
XRAY_DIR="/usr/local/bin"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CLASH_FILE="/root/clash.yaml"
CRED_FILE="/root/xray-info.txt"
SERVICE_NAME="xray"

# ==================== 模块加载 ====================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# BEGIN_MODULES
for _module in common os xray network config service report; do
    [[ -f "${LIB_DIR}/${_module}.sh" ]] ||
        { echo "缺少模块: ${LIB_DIR}/${_module}.sh" >&2; exit 1; }
    # shellcheck source=/dev/null
    . "${LIB_DIR}/${_module}.sh"
done
unset _module
# END_MODULES

# ==================== 主程序 ====================

main() {
    echo
    echo "=========================================="
    echo "       Xray VLESS REALITY Installer"
    echo "=========================================="
    echo

    check_prerequisites
    detect_os
    detect_arch
    install_dependencies
    install_xray
    generate_credentials
    get_public_ip
    check_port
    generate_server_config
    generate_clash_config
    save_credentials
    start_xray
    show_result

    echo
    success "全部部署完成"
}

main "$@"
