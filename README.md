# Xray 一键安装脚本

一键部署 **VLESS + XTLS-Vision + REALITY**，无需域名、无需证书，安装完成后直接输出客户端分享链接。

## 环境要求

- Linux：Debian / Ubuntu / CentOS / RHEL / Fedora / Arch 等（systemd），或 Alpine（OpenRC）
- 架构：x86_64、arm64、armv7、s390x、riscv64
- root 权限
- 服务器能访问 GitHub（用于下载 Xray）

## 快速开始

```bash
# 上传 install.sh 到服务器后执行
sudo bash install.sh
```

按提示输入端口和伪装域名，直接回车使用默认值（端口 `443`，伪装域名 `www.microsoft.com`）。

Alpine 默认没有 bash，可以直接用 `sh` 运行，脚本会自动安装 bash：

```bash
sh install.sh
```

全部使用默认值、无交互安装：

```bash
sudo bash install.sh -y
```

## 命令与参数

| 命令 | 说明 |
| --- | --- |
| `bash install.sh` | 安装（交互式） |
| `bash install.sh info` | 查看客户端配置和分享链接 |
| `bash install.sh upgrade` | 升级 Xray 到最新版（保留配置） |
| `bash install.sh uninstall` | 卸载 Xray 并删除配置 |
| `bash install.sh -h` | 查看帮助 |

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `-y`, `--yes` | 跳过所有交互，使用默认值或命令行参数 | - |
| `--port <端口>` | 监听端口 | `443` |
| `--sni <域名>` | REALITY 伪装域名 | `www.microsoft.com` |
| `--uuid <UUID>` | 指定用户 ID | 随机生成 |

示例：

```bash
sudo bash install.sh -y --port 8443 --sni www.apple.com
```

## 安装过程

1. 检查 root、系统、架构，自动安装依赖（curl、unzip、openssl）
2. 检查端口是否被占用、伪装域名是否支持 TLS1.3
3. 安装 Xray：systemd 系统使用官方脚本 [XTLS/Xray-install](https://github.com/XTLS/Xray-install)；Alpine 直接下载 [Xray-core](https://github.com/XTLS/Xray-core/releases) 最新版并注册 OpenRC 服务
4. 生成 UUID、x25519 密钥对、shortId
5. 写入配置并校验（已有配置会自动备份为 `config.json.bak.<时间戳>`）
6. 放行防火墙端口（ufw / firewalld）、开启 BBR
7. 启动服务并设置开机自启
8. 输出客户端配置和 `vless://` 分享链接

## 客户端配置

安装完成后会输出分享链接，复制导入客户端即可。支持的客户端：

- Windows：v2rayN
- macOS：V2rayU、FoXray、Clash Verge Rev（mihomo 内核）
- Android：v2rayNG
- iOS：Shadowrocket、FoXray、Stash

手动配置时的参数：

| 字段 | 值 |
| --- | --- |
| 协议 | VLESS |
| 地址 | 服务器 IP |
| 端口 | 安装时设置的端口 |
| UUID | 安装时生成 |
| 流控 (flow) | `xtls-rprx-vision` |
| 传输 | tcp |
| 安全 | reality |
| SNI | 伪装域名 |
| 指纹 (fingerprint) | chrome |
| 公钥 (publicKey) | 安装时生成 |
| ShortId | 安装时生成 |

随时查看：

```bash
bash install.sh info
```

## 文件位置

| 文件 | 路径 |
| --- | --- |
| Xray 程序 | `/usr/local/bin/xray` |
| 服务端配置 | `/usr/local/etc/xray/config.json` |
| 客户端信息 | `/usr/local/etc/xray/client-info.txt` |
| 规则文件 (geoip/geosite) | `/usr/local/share/xray/` |
| BBR 配置 | `/etc/sysctl.d/99-xray-bbr.conf` |
| OpenRC 服务（Alpine） | `/etc/init.d/xray` |
| 运行日志（Alpine） | `/var/log/xray/xray.log` |

## 常用运维命令

systemd 系统：

```bash
systemctl status xray      # 查看状态
systemctl restart xray     # 重启
systemctl stop xray        # 停止
journalctl -u xray -f      # 查看实时日志
```

Alpine（OpenRC）：

```bash
rc-service xray status             # 查看状态
rc-service xray restart            # 重启
rc-service xray stop               # 停止
tail -f /var/log/xray/xray.log     # 查看实时日志
```

升级 Xray 到最新版（保留配置）：

```bash
bash install.sh upgrade
```

## 常见问题

**连不上？**

1. 云服务商的安全组（阿里云、腾讯云、AWS 等）需要在控制台手动放行端口，脚本只能处理系统内的 ufw / firewalld
2. 检查服务是否运行：`systemctl status xray`（Alpine：`rc-service xray status`）
3. 查看日志：`journalctl -u xray -n 50`（Alpine：`tail -n 50 /var/log/xray/xray.log`）
4. 检查客户端时间是否准确，REALITY 对时间差比较敏感

**伪装域名怎么选？**

选择支持 TLS1.3 和 HTTP/2 的境外大站，最好与服务器在同一地区，例如 `www.microsoft.com`、`www.apple.com`、`www.amazon.com`。不要用被墙的网站，也不要用有 CDN 跳转的站点。

**端口被占用？**

用 `--port` 换一个端口，或先停掉占用 443 的服务（如 nginx）。

**Alpine 上提示获取最新版本失败？**

脚本通过 GitHub API 获取最新版本号，未登录时每小时有请求次数限制。稍后重试，或确认服务器能访问 `api.github.com`。

**分享链接里的 IP 不对？**

脚本通过公网接口获取 IP，如果服务器有多个出口 IP，请把链接中的地址手动改为正确的 IP。
