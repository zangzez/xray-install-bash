
#!/usr/bin/env bash
#
# Xray VLESS + REALITY + Vision 一键部署
# 支持 Debian / Ubuntu / Alpine
# 支持 amd64 / arm64 / arm32
#
# Usage:
#   chmod +x install-xray.sh
#   ./install-xray.sh
#
# 自定义:
#   XRAY_PORT=8443 XRAY_SNI=www.microsoft.com ./install-xray.sh

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

# ==================== 权限检查 ====================

[[ "${EUID}" -eq 0 ]] || die "请使用 root 用户执行"

[[ "$XRAY_PORT" =~ ^[0-9]+$ ]] &&
    (( XRAY_PORT >= 1 && XRAY_PORT <= 65535 )) ||
    die "端口不合法"

[[ "$XRAY_SNI" =~ ^[a-zA-Z0-9.-]+$ ]] ||
    die "SNI 格式不合法"

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

# ==================== 安装 Xray ====================

install_xray() {
    info "获取 Xray 最新版本..."

    local tag
    tag="$(curl -fsSL \
        https://api.github.com/repos/XTLS/Xray-core/releases/latest |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' |
        head -n 1)"

    [[ -n "$tag" ]] || die "无法获取 Xray 版本"

    info "Xray 版本: ${tag}"

    local package="Xray-linux-${ARCH}.zip"
    local url="https://github.com/XTLS/Xray-core/releases/download/${tag}/${package}"

    local tmp
    tmp="$(mktemp -d)"

    trap 'rm -rf "${tmp:-}"' EXIT

    info "下载 Xray..."

    curl -fL --retry 3 \
        "$url" -o "${tmp}/xray.zip" ||
        die "下载失败"

    unzip -oq "${tmp}/xray.zip" -d "${tmp}/xray" ||
        die "解压失败"

    [[ -f "${tmp}/xray/xray" ]] ||
        die "未找到 Xray 二进制文件"

    install -d -m 755 "$XRAY_DIR"
    install -m 755 "${tmp}/xray/xray" "${XRAY_DIR}/xray"

    if [[ -f "${tmp}/xray/geoip.dat" ]]; then
        install -d -m 755 /usr/local/share/xray
        install -m 644 "${tmp}/xray/geoip.dat" /usr/local/share/xray/
    fi

    if [[ -f "${tmp}/xray/geosite.dat" ]]; then
        install -m 644 "${tmp}/xray/geosite.dat" /usr/local/share/xray/
    fi

    XRAY_VERSION="$("${XRAY_DIR}/xray" version | head -n 1)"

    success "安装完成: ${XRAY_VERSION}"
}

# ==================== 生成认证信息 ====================

generate_credentials() {
    info "生成 UUID..."

    UUID="$("${XRAY_DIR}/xray" uuid | head -n 1)"

    [[ -n "$UUID" ]] || die "UUID 生成失败"

    info "生成 REALITY 密钥..."

    local output

    output="$("${XRAY_DIR}/xray" x25519 2>/dev/null)" ||
        die "REALITY 密钥生成失败"

    # 兼容不同 Xray 版本的输出格式
    PRIVATE_KEY="$(
        echo "$output" |
        grep -E '^(Private key|PrivateKey):' |
        awk '{print $NF}' |
        head -n 1
    )"

    PUBLIC_KEY="$(
        echo "$output" |
        grep -E '^(Public key|PublicKey|Password)' |
        awk '{print $NF}' |
        head -n 1
    )"

    [[ -n "$PRIVATE_KEY" ]] || die "无法解析私钥"
    [[ -n "$PUBLIC_KEY" ]] || die "无法解析公钥"

    SHORT_ID="$(openssl rand -hex 8)"

    success "UUID 生成成功"
    success "REALITY 密钥生成成功"
    success "Short ID 生成成功"
}

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

# ==================== 生成服务端配置 ====================

generate_server_config() {
    info "生成 Xray 服务端配置..."

    install -d -m 700 "$CONFIG_DIR"

    cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "target": "${XRAY_SNI}:443",
          "serverNames": [
            "${XRAY_SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

    chmod 600 "$CONFIG_FILE"

    # 测试配置是否合法
    "${XRAY_DIR}/xray" run -test -c "$CONFIG_FILE" ||
        die "Xray 配置校验失败"

    success "服务端配置生成并通过校验"
}

# ==================== 生成 Clash 配置 ====================

generate_clash_config() {
    info "生成 Clash 配置..."

    cat > "$CLASH_FILE" <<EOF
proxies:
  - name: "Xray-REALITY-${SERVER_IP}"
    type: vless
    server: ${SERVER_IP}
    port: ${XRAY_PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${XRAY_SNI}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: "${SHORT_ID}"
EOF

    chmod 600 "$CLASH_FILE"

    success "Clash 配置已生成: ${CLASH_FILE}"
}

# ==================== 保存节点信息 ====================

save_credentials() {
    cat > "$CRED_FILE" <<EOF
Xray Deployment Information
===========================

Server IP: ${SERVER_IP}
Port: ${XRAY_PORT}
Protocol: VLESS
Security: REALITY
Flow: xtls-rprx-vision
Network: TCP

UUID: ${UUID}
Private Key: ${PRIVATE_KEY}
Public Key: ${PUBLIC_KEY}
Short ID: ${SHORT_ID}
SNI: ${XRAY_SNI}

Clash Config: ${CLASH_FILE}
Server Config: ${CONFIG_FILE}
EOF

    chmod 600 "$CRED_FILE"
}

# ==================== 配置 systemd ====================

setup_systemd() {
    info "配置 systemd 服务..."

    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${XRAY_DIR}/xray run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
}

# ==================== 配置 OpenRC ====================

setup_openrc() {
    info "配置 OpenRC 服务..."

    cat > /etc/init.d/xray <<EOF
#!/sbin/openrc-run

name="Xray"
description="Xray Service"

command="${XRAY_DIR}/xray"
command_args="run -c ${CONFIG_FILE}"
command_background=true
pidfile="/run/xray.pid"

depend() {
    need net
}
EOF

    chmod 755 /etc/init.d/xray

    rc-update add xray default
    rc-service xray restart || rc-service xray start
}

# ==================== 启动服务 ====================

start_xray() {
    info "启动 Xray..."

    if [[ "$INIT" == "systemd" ]]; then
        setup_systemd
    else
        setup_openrc
    fi

    sleep 2

    if [[ "$INIT" == "systemd" ]]; then
        systemctl is-active --quiet xray ||
            die "Xray 启动失败，请查看 journalctl -u xray"
    else
        rc-service xray status >/dev/null 2>&1 ||
            die "Xray 启动失败，请查看 OpenRC 日志"
    fi

    success "Xray 服务运行正常"
}

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

# ==================== 主程序 ====================

main() {
    echo
    echo "=========================================="
    echo "       Xray VLESS REALITY Installer"
    echo "=========================================="
    echo

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

