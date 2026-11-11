#!/usr/bin/env bash
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
