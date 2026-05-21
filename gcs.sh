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

# 启动 Tailscale 容器
docker run -d --rm --net=host \
    --name "${NAME}-tailscale" \
    --cap-add NET_ADMIN \
    --device /dev/net/tun \
    -e TS_AUTHKEY="$TAILSCALE_AUTHKEY" \
    -e TS_STATE_DIR="/var/lib/tailscale" \
    -v "$HOME/.tailscale_state:/var/lib/tailscale" \
    tailscale/tailscale:latest

# 启动 LXDE VNC + 中文 + SSH + RDP 容器
docker run -d --name "${NAME}-vnc" --net=host \
    -v "$HOME:/root" \
    -e VNC_PASSWORD="$VNC_PASS" \
    -e SSH_PASSWORD="$SSH_PASS" \
    -e LANG="zh_CN.UTF-8" \
    -e DISPLAY_WIDTH=1280 -e DISPLAY_HEIGHT=720 \
    -p 8080:8080 \
    $DOCKER_IMAGE /bin/sh -c "
        # 安装中文支持、SSH、RDP
        apt-get update && apt-get install -y language-pack-zh-hans locales sudo openssh-server xrdp \
        && locale-gen zh_CN.UTF-8 \
        && update-locale LANG=zh_CN.UTF-8 \
        # SSH 配置
        && mkdir -p /var/run/sshd \
        && echo 'root:$SSH_PASSWORD' | chpasswd \
        && sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
        && sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
        && service ssh start \
        # 启动 xrdp
        && service xrdp start \
        # 启动 VNC Server
        && vncserver :1 -geometry ${RESOLUTION} -depth 24 \
        && echo '=== LXDE + VNC + SSH + RDP 已就绪 ==='"
        
echo "=== 启动完成 ==="
echo "VNC（Web）访问: http://127.0.0.1:8080 , 密码: $VNC_PASS"
echo "SSH 访问: ssh root@<Tailscale-IP> , 密码: $SSH_PASS"
echo "RDP 访问: <Tailscale-IP>:3389 , 分辨率: $RESOLUTION"
