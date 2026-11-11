#!/usr/bin/env bash
# ==================== 获取公网 IP ====================

get_public_ip() {
    info "检测公网 IPv4..."

    SERVER_IP="$(
        curl -4fsSL --connect-timeout 5 --max-time 10 \
        https://api.ipify.org 2>/dev/null || true
    )"

    if [[ -z "$SERVER_IP" ]]; then
        warn "公网 IP 自动检测失败"
        read -r -p "请输入 VPS 公网 IPv4: " SERVER_IP
    fi

    [[ -n "$SERVER_IP" ]] || die "公网 IP 不能为空"

    success "公网 IP: ${SERVER_IP}"
}

# ==================== 检查端口 ====================

check_port() {
    info "检查 TCP ${XRAY_PORT} 端口..."

    if command -v ss >/dev/null 2>&1; then
        if ss -H -lnt "sport = :${XRAY_PORT}" | grep -q .; then
            die "TCP ${XRAY_PORT} 已被占用，请更换端口"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -lnt 2>/dev/null |
            grep -E "[:.]${XRAY_PORT}[[:space:]]" | grep -q .; then
            die "TCP ${XRAY_PORT} 已被占用"
        fi
    else
        warn "无法检查端口占用，请确认端口可用"
    fi
}
