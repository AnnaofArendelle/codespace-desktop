#!/bin/sh

# --- 用户配置 ---
NAME="tailscale-gcsvnc"
PASS="password"
DOCKER_IMAGE="dorowu/ubuntu-desktop-lxde-vnc"
TAILSCALE_AUTHKEY_FILE="$HOME/.tailscale_authkey"
VNC_RESOLUTION="1280x720"
RDP_RESOLUTION="1280x720"
# --- 用户配置结束 ---

# 1️⃣ 读取或输入 Tailscale Auth Key
if [ ! -f "$TAILSCALE_AUTHKEY_FILE" ]; then
    echo "Enter your Tailscale Auth Key (will be saved in $TAILSCALE_AUTHKEY_FILE):"
    read -r TAILSCALE_AUTHKEY
    echo "$TAILSCALE_AUTHKEY" > "$TAILSCALE_AUTHKEY_FILE"
else
    TAILSCALE_AUTHKEY=$(cat "$TAILSCALE_AUTHKEY_FILE")
fi

# 2️⃣ 启动 Tailscale 容器
docker run -d --rm --net=host \
    --name "${NAME}-tailscale" \
    --cap-add NET_ADMIN \
    --device /dev/net/tun \
    -e TS_AUTHKEY="$TAILSCALE_AUTHKEY" \
    -e TS_STATE_DIR="/var/lib/tailscale" \
    -v "$HOME/.tailscale_state:/var/lib/tailscale" \
    tailscale/tailscale:latest

# 3️⃣ 启动 LXDE VNC + 中文 + SSH + RDP 容器
docker run -d --name "${NAME}-vnc" --net=host \
    -v "$HOME:/root" \
    -e VNC_PASSWORD="$PASS" \
    -e LANG="zh_CN.UTF-8" \
    -e DISPLAY_WIDTH=1280 -e DISPLAY_HEIGHT=720 \
    -p 8080:8080 \   # Cloud Shell Web 端口访问
    $DOCKER_IMAGE \
    /bin/sh -c "
        # 安装中文支持
        apt-get update && apt-get install -y language-pack-zh-hans locales \
        && locale-gen zh_CN.UTF-8 \
        && update-locale LANG=zh_CN.UTF-8 \
        # 安装 SSH
        && apt-get install -y openssh-server \
        && mkdir -p /var/run/sshd \
        # 安装 xrdp
        && apt-get install -y xrdp \
        && sed -i 's/^#*xrdp.*//' /etc/xrdp/xrdp.ini \
        && echo 'startlxde' > /etc/xrdp/startwm.sh \
        && echo 'export LANG=zh_CN.UTF-8' >> /etc/xrdp/startwm.sh \
        # 启动服务
        && service ssh start \
        && service xrdp start \
        # 启动 VNC server（1280x720）
        && vncserver :1 -geometry ${VNC_RESOLUTION} -depth 24 \
        && echo 'Ready'"

# 4️⃣ 性能优化（内核调优）
# 启用 TCP Fast Open
sudo sysctl -w net.ipv4.tcp_fastopen=3
# 启用 BBR 拥塞控制
sudo modprobe tcp_bbr
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
sudo sysctl -w net.core.default_qdisc=fq

echo "=== 完成启动 ==="
echo "VNC: http://127.0.0.1:8080 (密码: $PASS)"
echo "SSH: ssh root@<CloudShell-Tailscale-IP>"
echo "RDP: connect to CloudShell-Tailscale-IP:3389, resolution ${RDP_RESOLUTION}"
