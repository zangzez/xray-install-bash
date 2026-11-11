#!/usr/bin/env bash
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
