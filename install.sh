#!/usr/bin/env bash
#
# Xray 一键安装脚本（VLESS + XTLS-Vision + REALITY）
# @author zangyuantu Date: 2026/11/11 Time: 05:56
#
# 用法:
#   bash install.sh                 安装（交互式，回车使用默认值）
#   bash install.sh -y              安装（全部使用默认值，无交互）
#   bash install.sh --port 8443 --sni www.apple.com
#   bash install.sh info            查看当前配置和分享链接
#   bash install.sh upgrade         升级 Xray 到最新版（保留配置）
#   bash install.sh uninstall       卸载
#

# Alpine 默认没有 bash：用 sh 运行时自动安装 bash 并切换过去。
# 这一段必须保持 POSIX sh 语法，放在所有 bash 专有语法之前。
if [ -z "${BASH_VERSION:-}" ]; then
    if ! command -v bash >/dev/null 2>&1; then
        if command -v apk >/dev/null 2>&1; then
            echo "正在安装 bash..."
            apk add --no-cache bash >/dev/null || { echo "安装 bash 失败"; exit 1; }
        else
            echo "请使用 bash 运行本脚本"; exit 1
        fi
    fi
    exec bash "$0" "$@"
fi

set -euo pipefail

# ---------- 默认参数 ----------
PORT=443
SNI="www.microsoft.com"
UUID=""
NON_INTERACTIVE=0
ACTION="install"
INIT=""   # systemd | openrc

XRAY_BIN="/usr/local/bin/xray"
XRAY_ASSET_DIR="/usr/local/share/xray"
XRAY_CONF_DIR="/usr/local/etc/xray"
XRAY_CONF="${XRAY_CONF_DIR}/config.json"
INFO_FILE="${XRAY_CONF_DIR}/client-info.txt"
OPENRC_SERVICE="/etc/init.d/xray"
OPENRC_LOG="/var/log/xray/xray.log"
BBR_CONF="/etc/sysctl.d/99-xray-bbr.conf"
OFFICIAL_SCRIPT="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
RELEASE_API="https://api.github.com/repos/XTLS/Xray-core/releases/latest"

# ---------- 输出 ----------
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
die()    { red "错误: $*"; exit 1; }

usage() {
    sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------- 参数解析 ----------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|info|upgrade|uninstall) ACTION="$1" ;;
            -y|--yes)   NON_INTERACTIVE=1 ;;
            --port)     PORT="${2:?--port 需要参数}"; shift ;;
            --sni)      SNI="${2:?--sni 需要参数}"; shift ;;
            --uuid)     UUID="${2:?--uuid 需要参数}"; shift ;;
            -h|--help)  usage ;;
            *)          die "未知参数: $1（使用 -h 查看帮助）" ;;
        esac
        shift
    done
}

# ---------- 环境检查 ----------
check_root() {
    [[ $EUID -eq 0 ]] || die "请使用 root 运行（sudo bash $0）"
}

detect_init() {
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        INIT="systemd"
    elif command -v rc-service >/dev/null 2>&1 && [[ -x /sbin/openrc-run ]]; then
        INIT="openrc"
    else
        die "仅支持 systemd 或 OpenRC 系统"
    fi
}

check_os() {
    [[ "$(uname -s)" == "Linux" ]] || die "仅支持 Linux"
    xray_arch >/dev/null
    detect_init
}

# 映射到 Xray release 包的架构名
xray_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "64" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l|armv7)  echo "arm32-v7a" ;;
        s390x)         echo "s390x" ;;
        riscv64)       echo "riscv64" ;;
        *) die "不支持的架构: $(uname -m)" ;;
    esac
}

install_deps() {
    local missing=()
    for p in curl unzip openssl; do
        command -v "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    [[ ${#missing[@]} -eq 0 ]] && return

    yellow "安装依赖: ${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y curl unzip openssl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl unzip openssl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl unzip openssl
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl unzip openssl ca-certificates
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm curl unzip openssl
    else
        die "无法识别的包管理器，请手动安装: ${missing[*]}"
    fi
}

# ---------- 交互输入 ----------
prompt() {
    # prompt <变量名> <提示> <默认值>
    local __var="$1" __msg="$2" __def="$3" __input
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        printf -v "$__var" '%s' "$__def"
        return
    fi
    read -r -p "${__msg} [默认 ${__def}]: " __input || true
    printf -v "$__var" '%s' "${__input:-$__def}"
}

collect_input() {
    prompt PORT "监听端口" "$PORT"
    [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "端口无效: $PORT"
    if port_in_use "$PORT"; then
        die "端口 $PORT 已被占用，请换一个端口（--port）"
    fi

    prompt SNI "伪装域名 (需支持 TLS1.3 + H2 的境外站点)" "$SNI"
}

port_in_use() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$"
    else
        return 1
    fi
}

check_sni() {
    yellow "检测伪装域名 ${SNI} 的 TLS1.3 支持..."
    if echo | timeout 8 openssl s_client -connect "${SNI}:443" -servername "${SNI}" -tls1_3 >/dev/null 2>&1; then
        green "  ${SNI} 支持 TLS1.3"
    else
        yellow "  警告: 无法确认 ${SNI} 支持 TLS1.3，Reality 可能无法正常工作"
    fi
}

# ---------- 安装 Xray ----------
install_xray() {
    if [[ "$INIT" == "systemd" ]]; then
        yellow "下载并安装 Xray（官方脚本）..."
        bash -c "$(curl -fsSL "$OFFICIAL_SCRIPT")" @ install
    else
        install_xray_release
        write_openrc_service
    fi
    [[ -x "$XRAY_BIN" ]] || die "Xray 安装失败"
    green "Xray 版本: $("$XRAY_BIN" version | head -n1)"
}

# 官方脚本依赖 systemd，OpenRC 系统（Alpine）直接从 GitHub Release 安装
install_xray_release() {
    local arch version tmp
    arch="$(xray_arch)"
    version="$(curl -fsSL "$RELEASE_API" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')" || true
    [[ -n "$version" ]] || die "获取 Xray 最新版本失败（GitHub API 不可达或被限流）"

    yellow "下载 Xray ${version} (linux-${arch})..."
    tmp="$(mktemp -d)"
    curl -fL --retry 3 -o "$tmp/xray.zip" \
        "https://github.com/XTLS/Xray-core/releases/download/${version}/Xray-linux-${arch}.zip" \
        || die "下载 Xray 失败"
    unzip -qo "$tmp/xray.zip" -d "$tmp/xray" || die "解压失败"

    install -m 755 "$tmp/xray/xray" "$XRAY_BIN"
    mkdir -p "$XRAY_ASSET_DIR"
    install -m 644 "$tmp/xray/geoip.dat" "$tmp/xray/geosite.dat" "$XRAY_ASSET_DIR/"
    rm -rf "$tmp"
}

write_openrc_service() {
    mkdir -p "$(dirname "$OPENRC_LOG")"
    cat >"$OPENRC_SERVICE" <<EOF
#!/sbin/openrc-run

name="xray"
description="Xray Service"
command="${XRAY_BIN}"
command_args="run -config ${XRAY_CONF}"
command_background="yes"
pidfile="/run/xray.pid"
output_log="${OPENRC_LOG}"
error_log="${OPENRC_LOG}"
export XRAY_LOCATION_ASSET="${XRAY_ASSET_DIR}"

depend() {
    need net
    after firewall
}
EOF
    chmod 755 "$OPENRC_SERVICE"
}

# ---------- 生成密钥与配置 ----------
gen_keys() {
    [[ -n "$UUID" ]] || UUID="$("$XRAY_BIN" uuid)"

    local out
    out="$("$XRAY_BIN" x25519)"
    # 兼容新旧版本输出格式：
    #   旧: "Private key: xxx" / "Public key: yyy"
    #   新: "PrivateKey: xxx"  / "Password: yyy"
    PRIVATE_KEY="$(awk -F': *' 'tolower($1) ~ /^private ?key$/ {print $2}' <<<"$out")"
    PUBLIC_KEY="$(awk -F': *' 'tolower($1) ~ /^(public ?key|password)$/ {print $2}' <<<"$out")"
    [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || die "生成 x25519 密钥失败: $out"

    SHORT_ID="$(openssl rand -hex 8)"
}

write_config() {
    mkdir -p "$XRAY_CONF_DIR"
    [[ -f "$XRAY_CONF" ]] && cp "$XRAY_CONF" "${XRAY_CONF}.bak.$(date +%s)"

    cat >"$XRAY_CONF" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
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
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" },
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" }
    ]
  }
}
EOF
    chmod 644 "$XRAY_CONF"

    XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" "$XRAY_BIN" run -test -config "$XRAY_CONF" >/dev/null \
        || die "配置校验失败: $XRAY_CONF"
}

# ---------- 防火墙 / BBR ----------
open_firewall() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "${PORT}/tcp" >/dev/null && green "ufw 已放行 ${PORT}/tcp"
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null
        firewall-cmd --reload >/dev/null && green "firewalld 已放行 ${PORT}/tcp"
    fi
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        return
    fi
    if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        modprobe tcp_bbr 2>/dev/null || true
    fi
    if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        mkdir -p "$(dirname "$BBR_CONF")"
        cat >"$BBR_CONF" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
        sysctl -p "$BBR_CONF" >/dev/null 2>&1 || true
        green "已开启 BBR"
    fi
}

# ---------- 服务管理（systemd / OpenRC） ----------
service_active() {
    if [[ "$INIT" == "systemd" ]]; then
        systemctl is-active --quiet xray
    else
        rc-service xray status >/dev/null 2>&1
    fi
}

show_service_log() {
    if [[ "$INIT" == "systemd" ]]; then
        journalctl -u xray --no-pager -n 30
    else
        tail -n 30 "$OPENRC_LOG" 2>/dev/null || true
    fi
}

start_service() {
    if [[ "$INIT" == "systemd" ]]; then
        systemctl daemon-reload
        systemctl enable xray >/dev/null 2>&1
        systemctl restart xray
    else
        rc-update add xray default >/dev/null 2>&1 || true
        rc-service xray restart >/dev/null 2>&1 || rc-service xray start
    fi
    sleep 1
    service_active || { show_service_log; die "Xray 启动失败"; }
    green "Xray 服务已启动"
}

# ---------- 输出客户端信息 ----------
get_public_ip() {
    local ip
    for url in https://api.ipify.org https://ifconfig.me https://ip.sb; do
        ip="$(curl -4 -fsS --max-time 5 "$url" 2>/dev/null || true)"
        [[ -n "$ip" ]] && { echo "$ip"; return; }
    done
    for url in https://api64.ipify.org https://ifconfig.me; do
        ip="$(curl -6 -fsS --max-time 5 "$url" 2>/dev/null || true)"
        [[ -n "$ip" ]] && { echo "[$ip]"; return; }
    done
    echo "你的服务器IP"
}

save_and_show_info() {
    local ip link
    ip="$(get_public_ip)"
    link="vless://${UUID}@${ip}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#xray-reality-${ip}"

    cat >"$INFO_FILE" <<EOF
================ Xray 客户端配置 ================
地址 (address)     : ${ip}
端口 (port)        : ${PORT}
用户ID (uuid)      : ${UUID}
流控 (flow)        : xtls-rprx-vision
传输 (network)     : tcp
安全 (security)    : reality
SNI (serverName)   : ${SNI}
指纹 (fingerprint) : chrome
公钥 (publicKey)   : ${PUBLIC_KEY}
ShortId            : ${SHORT_ID}
------------------------------------------------
分享链接:
${link}
================================================
EOF
    chmod 600 "$INFO_FILE"
    echo
    cat "$INFO_FILE"
    echo
    yellow "以上信息已保存到 ${INFO_FILE}，可随时运行 'bash $0 info' 查看"
}

# ---------- 子命令 ----------
do_install() {
    check_root
    check_os
    install_deps
    collect_input
    check_sni
    install_xray
    gen_keys
    write_config
    open_firewall
    enable_bbr
    start_service
    save_and_show_info
}

do_info() {
    [[ -f "$INFO_FILE" ]] || die "未找到配置信息，请先安装"
    detect_init
    cat "$INFO_FILE"
    echo
    if service_active; then green "服务状态: 运行中"; else red "服务状态: 未运行"; fi
}

do_upgrade() {
    check_root
    check_os
    [[ -x "$XRAY_BIN" ]] || die "未安装 Xray，请先安装"
    install_deps
    yellow "当前版本: $("$XRAY_BIN" version | head -n1)"
    if [[ "$INIT" == "systemd" ]]; then
        bash -c "$(curl -fsSL "$OFFICIAL_SCRIPT")" @ install
    else
        install_xray_release
    fi
    start_service
    green "升级后版本: $("$XRAY_BIN" version | head -n1)"
}

do_uninstall() {
    check_root
    detect_init
    if [[ $NON_INTERACTIVE -eq 0 ]]; then
        local ans
        read -r -p "确认卸载 Xray 并删除配置？[y/N]: " ans || true
        [[ "$ans" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }
    fi
    if [[ "$INIT" == "systemd" ]]; then
        bash -c "$(curl -fsSL "$OFFICIAL_SCRIPT")" @ remove --purge
    else
        rc-service xray stop >/dev/null 2>&1 || true
        rc-update del xray default >/dev/null 2>&1 || true
        rm -f "$OPENRC_SERVICE" "$XRAY_BIN"
        rm -rf "$XRAY_ASSET_DIR" "$XRAY_CONF_DIR" "$(dirname "$OPENRC_LOG")"
    fi
    rm -f "$BBR_CONF"
    green "Xray 已卸载"
}

main() {
    parse_args "$@"
    case "$ACTION" in
        install)   do_install ;;
        info)      do_info ;;
        upgrade)   do_upgrade ;;
        uninstall) do_uninstall ;;
    esac
}

main "$@"
