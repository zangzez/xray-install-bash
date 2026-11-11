#!/usr/bin/env bash
# ==================== 输出结果 ====================

show_result() {
    echo
    echo "=========================================="
    echo "          Xray 部署成功"
    echo "=========================================="

    echo
    echo "服务器信息"
    echo "------------------------------------------"
    echo "IP:           ${SERVER_IP}"
    echo "Port:         ${XRAY_PORT}"
    echo "Protocol:     VLESS"
    echo "Security:     REALITY"
    echo "Network:      TCP"
    echo "Flow:         xtls-rprx-vision"
    echo "SNI:          ${XRAY_SNI}"

    echo
    echo "认证信息"
    echo "------------------------------------------"
    echo "UUID:         ${UUID}"
    echo "Public Key:   ${PUBLIC_KEY}"
    echo "Short ID:     ${SHORT_ID}"

    echo
    echo "文件位置"
    echo "------------------------------------------"
    echo "Clash:        ${CLASH_FILE}"
    echo "Server:       ${CONFIG_FILE}"
    echo "Info:         ${CRED_FILE}"

    echo
    echo "=========================================="
    echo " Clash 配置"
    echo "=========================================="

    cat "$CLASH_FILE"

    echo
    echo "=========================================="
    echo "注意：Private Key 仅保存在服务端配置中"
    echo "=========================================="
}
