#!/bin/sh

# === 用户配置 ===
NAME="tailscale-gcsvnc"
VNC_PASS="password"         # VNC密码
SSH_PASS="password"         # SSH密码
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

# 拉取 Docker 镜像
docker pull $DOCKER_IMAGE
docker pull tailscale/tailscale:latest

# 启动 Tailscale 容器（保持不变）
docker run -d --rm --net=host \
    --name "${NAME}-tailscale" \
    --cap-add NET_ADMIN \
    --device /dev/net/tun \
    -e TS_AUTHKEY="$TAILSCALE_AUTHKEY" \
    -e TS_STATE_DIR="/var/lib/tailscale" \
    -v "$HOME/.tailscale_state:/var/lib/tailscale" \
    tailscale/tailscale:latest

# 启动 LXDE VNC + 中文 + SSH + RDP 容器（修正版）
docker run -d --name "${NAME}-vnc" --net=host \
    -v "$HOME:/root" \
    -e VNC_PASSWORD="$VNC_PASS" \
    -e SSH_PASSWORD="$SSH_PASS" \
    -e LANG="zh_CN.UTF-8" \
    -e DISPLAY_WIDTH=1280 -e DISPLAY_HEIGHT=720 \
    $DOCKER_IMAGE /bin/bash -c "
        # 安装中文支持、SSH、RDP
        apt-get update && apt-get install -y language-pack-zh-hans locales sudo openssh-server xrdp
        locale-gen zh_CN.UTF-8
        update-locale LANG=zh_CN.UTF-8
        # SSH 配置
        mkdir -p /var/run/sshd
        # 修正：使用双引号让 $SSH_PASSWORD 变量展开
        echo \"root:$SSH_PASSWORD\" | chpasswd
        sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
        sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        # 启动 SSH 和 RDP 服务（后台）
        service ssh start
        service xrdp start
        # 交给原镜像的启动脚本，保持容器前台运行（VNC、noVNC 等）
        exec /start.sh
    "

echo "=== 启动完成 ==="
echo "VNC（Web）访问: http://<Tailscale-IP>:8080 , 密码: $VNC_PASS"
echo "SSH 访问: ssh root@<Tailscale-IP> , 密码: $SSH_PASS"
echo "RDP 访问: <Tailscale-IP>:3389 , 分辨率: $RESOLUTION"
echo "请等待 1-2 分钟让服务完全启动。"
