#!/bin/sh

# === 用户配置 ===
NAME="tailscale-gcsvnc"
VNC_PASS="password"         # 修改为你的 VNC 密码
SSH_PASS="password"         # 修改为你的 SSH 密码
DOCKER_IMAGE="dorowu/ubuntu-desktop-lxde-vnc"
TAILSCALE_AUTHKEY_FILE="$HOME/.tailscale_authkey"
RESOLUTION="1280x720"
# === 用户配置结束 ===

# 清理已有容器
docker rm -f "${NAME}-tailscale" "${NAME}-vnc" >/dev/null 2>&1

# 读取或输入 Tailscale Auth Key
if [ ! -f "$TAILSCALE_AUTHKEY_FILE" ]; then
    echo "请输入 Tailscale Auth Key（仅保存一次）:"
    read -r TAILSCALE_AUTHKEY
    echo "$TAILSCALE_AUTHKEY" > "$TAILSCALE_AUTHKEY_FILE"
else
    TAILSCALE_AUTHKEY=$(cat "$TAILSCALE_AUTHKEY_FILE")
fi

# 拉取镜像
docker pull $DOCKER_IMAGE
docker pull tailscale/tailscale:latest

# 启动 Tailscale 容器
docker run -d --rm --net=host \
    --name "${NAME}-tailscale" \
    --cap-add NET_ADMIN \
    --device /dev/net/tun \
    -e TS_AUTHKEY="$TAILSCALE_AUTHKEY" \
    -e TS_STATE_DIR="/var/lib/tailscale" \
    -v "$HOME/.tailscale_state:/var/lib/tailscale" \
    tailscale/tailscale:latest

# 创建自定义启动脚本（用于 VNC 容器）
cat > /tmp/custom_start.sh << 'EOF'
#!/bin/bash
set -e

# 1. 杀除可能占用 22 端口的进程
if fuser 22/tcp 2>/dev/null; then
    echo "Port 22 is occupied, killing the process..."
    fuser -k 22/tcp
fi

# 2. 安装 SSH 并配置
apt-get update
apt-get install -y openssh-server language-pack-zh-hans locales sudo xrdp

# 确保 locale 设置
locale-gen zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8

# 准备 SSH 运行目录
mkdir -p /var/run/sshd

# 设置 root 密码
echo "root:${SSH_PASSWORD}" | chpasswd

# 修改 SSH 配置允许密码登录
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 3. 将 SSH 添加到 supervisor 管理（确保持久运行）
cat > /etc/supervisor/conf.d/ssh.conf << CONF
[program:ssh]
command=/usr/sbin/sshd -D
process_name=sshd
autostart=true
autorestart=true
user=root
CONF

# 4. 启动 xrdp（可选，也可放入 supervisor）
service xrdp start

# 5. 原始镜像的入口脚本会启动 supervisor（内含 VNC、noVNC 等）
exec /start.sh
EOF

chmod +x /tmp/custom_start.sh

# 启动 VNC 容器（使用自定义启动脚本）
docker run -d --name "${NAME}-vnc" --net=host \
    -v "$HOME:/root" \
    -e VNC_PASSWORD="$VNC_PASS" \
    -e SSH_PASSWORD="$SSH_PASS" \
    -e LANG="zh_CN.UTF-8" \
    -e DISPLAY_WIDTH=1280 -e DISPLAY_HEIGHT=720 \
    -v /tmp/custom_start.sh:/custom_start.sh \
    $DOCKER_IMAGE /bin/bash /custom_start.sh

echo "=== 启动完成，请等待 30 秒初始化 ==="
echo "VNC（Web）访问: http://127.0.0.1:8080 (Cloud Shell 中需点击 Web 预览) 密码: $VNC_PASS"
echo "SSH 访问: ssh root@<Tailscale-IP> 密码: $SSH_PASS"
echo "RDP 访问: <Tailscale-IP>:3389 分辨率: $RESOLUTION"
