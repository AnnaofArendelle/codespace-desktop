#!/bin/sh

# --- 用户配置区 ---
NAME="tailscale-gcsvnc"
PASS="password"   # 请修改你的VNC密码
DOCKER_IMAGE="dorowu/ubuntu-desktop-lxde-vnc"  # LXDE VNC 镜像
# --- 用户配置区结束 ---

TAILSCALE_AUTHKEY="" # 通过环境变量或手动输入

setup() {
    echo "=== Starting setup for ${NAME} ==="

    # 1. 检查并获取 Tailscale Auth Key
    if [ -z "$TAILSCALE_AUTHKEY" ]; then
        echo "WARNING: You need a Tailscale Auth Key to proceed."
        echo "Please visit https://login.tailscale.com/admin/settings/keys to generate one."
        printf "Enter your Auth Key: "
        read -r TAILSCALE_AUTHKEY
        if [ -z "$TAILSCALE_AUTHKEY" ]; then
            echo "Error: An Auth Key is required for automated setup."
            exit 1
        fi
    fi

    # 2. 启动Tailscale容器 (使用主机网络)
    echo "Joining Tailscale network..."
    docker run -d \
        --rm \
        --net=host \
        --name "${NAME}-tailscale" \
        --cap-add NET_ADMIN \
        --device /dev/net/tun \
        -e TS_AUTHKEY="$TAILSCALE_AUTHKEY" \
        -e TS_STATE_DIR="/var/lib/tailscale" \
        -v "${HOME}/.tailscale_state:/var/lib/tailscale" \
        tailscale/tailscale:latest
    echo "Tailscale container started. Waiting for network to be ready..."

    # 3. 启动 LXDE VNC Docker 镜像
    echo "Starting LXDE VNC container..."
    docker run -d \
        --name "${NAME}-vnc" \
        --net=host \
        -v $HOME:/root \
        -e VNC_PASSWORD="$PASS" \
        $DOCKER_IMAGE
    echo "LXDE VNC container started."
    echo "You can now connect via VNC using Tailscale IP on port 5900."
}

ifnotsetup() {
    # 1. 检查 Tailscale 容器
    if ! docker ps --format '{{.Names}}' | grep -q "^${NAME}-tailscale$"; then
        echo "Warning: Tailscale container is not running. Attempting to start..."
        if [ -f "$HOME/.tailscale_state/authkey" ]; then
            docker run -d \
                --rm \
                --net=host \
                --name "${NAME}-tailscale" \
                --cap-add NET_ADMIN \
                --device /dev/net/tun \
                -e TS_AUTHKEY="$(cat $HOME/.tailscale_state/authkey)" \
                -e TS_STATE_DIR="/var/lib/tailscale" \
                -v "${HOME}/.tailscale_state:/var/lib/tailscale" \
                tailscale/tailscale:latest
            echo "Tailscale container restarted."
        else
            echo "Error: Cannot restart Tailscale. Please run setup again."
            exit 1
        fi
    fi

    # 2. 检查 LXDE VNC 容器
    if ! docker ps --format '{{.Names}}' | grep -q "^${NAME}-vnc$"; then
        echo "Warning: LXDE VNC container is not running. Starting..."
        docker run -d \
            --name "${NAME}-vnc" \
            --net=host \
            -v $HOME:/root \
            -e VNC_PASSWORD="$PASS" \
            $DOCKER_IMAGE
        echo "LXDE VNC container started."
    fi
}

case "$1" in
    setup)   setup ;;
    "")      ifnotsetup ;;
    kill)    docker stop "${NAME}-vnc" ; docker stop "${NAME}-tailscale" ;;
    killall) docker stop "${NAME}-vnc" ; docker stop "${NAME}-tailscale" ;;
    *)
        echo "Usage: $0 [setup|kill|killall]"
        exit 1
        ;;
esac
