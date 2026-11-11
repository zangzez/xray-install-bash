#!/usr/bin/env bash
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
