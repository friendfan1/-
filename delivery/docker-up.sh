#!/bin/sh
# Docker 18.09-compatible offline startup; no Compose, buildx or host Python.
set -eu
TASK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TASK_ENV=${1:-"$TASK_DIR/docker.env"}
TASK_IMAGE=${APP_IMAGE:-asset-console:1.1-arm64}
TASK_VOLUME=${APP_DATA_VOLUME:-asset-console-data}
TASK_WEB=${APP_WEB_CONTAINER:-asset-console-web}
TASK_MONITOR=${APP_MONITOR_CONTAINER:-asset-console-monitor}
TASK_ATTEMPTED_WEB=0
TASK_ATTEMPTED_MONITOR=0
TASK_INSTANCE="$TASK_WEB:$$:$(date +%s)"

fail() { printf '%s\n' "$*" >&2; exit 1; }

valid_name() {
    case "$1" in ''|*[!a-zA-Z0-9_.-]*|-*|.*) return 1 ;; *) return 0 ;; esac
}

remove_this_attempt() {
    TASK_REMOVE_NAME=$1
    TASK_REMOVE_ROLE=$2
    TASK_REMOVE_TAGS=$(docker inspect --format '{{index .Config.Labels "org.asset-console.managed"}}|{{index .Config.Labels "org.asset-console.role"}}|{{index .Config.Labels "org.asset-console.instance"}}' "$TASK_REMOVE_NAME" 2>/dev/null) || return 0
    # A failed docker run can leave a Created container. Remove it only if
    # all labels identify this exact invocation; never remove a racing peer.
    if [ "$TASK_REMOVE_TAGS" = "true|$TASK_REMOVE_ROLE|$TASK_INSTANCE" ]; then
        docker rm -f "$TASK_REMOVE_NAME" >/dev/null 2>&1 || :
    fi
}

cleanup_failed_start() {
    TASK_STATUS=$?
    if [ "$TASK_STATUS" -ne 0 ]; then
        printf '%s\n' '启动未完成；仅清理本次启动的容器，数据卷保留。' >&2
        if [ "$TASK_ATTEMPTED_MONITOR" -eq 1 ]; then remove_this_attempt "$TASK_MONITOR" monitor; fi
        if [ "$TASK_ATTEMPTED_WEB" -eq 1 ]; then remove_this_attempt "$TASK_WEB" web; fi
    fi
}

command -v docker >/dev/null 2>&1 || fail '未安装 Docker；本部署需要宿主机已有 Docker 18.09 或更新版本。'
[ "$(uname -s)" = Linux ] || fail '本脚本使用 Linux host 网络，请在 Linux 服务器执行。'
[ -r "$TASK_ENV" ] || fail "未找到配置文件：$TASK_ENV；请先复制 docker.env.example 并填写实际服务器 IP。"
[ "$#" -le 1 ] || fail '用法：sh deploy/docker-up.sh [配置文件路径]'
valid_name "$TASK_VOLUME" || fail '数据卷名称不合法。'
valid_name "$TASK_WEB" || fail 'Web 容器名称不合法。'
valid_name "$TASK_MONITOR" || fail '检测容器名称不合法。'
[ "$TASK_WEB" != "$TASK_MONITOR" ] || fail '两个容器名称不能相同。'
docker info >/dev/null 2>&1 || fail '无法连接 Docker 服务，请检查服务状态和当前账号权限。'

case "$(uname -m)" in
    aarch64|arm64) TASK_HOST_ARCH=arm64 ;;
    x86_64|amd64) TASK_HOST_ARCH=amd64 ;;
    *) fail '当前宿主机 CPU 架构未受此脚本支持。' ;;
esac
TASK_EXPECTED=${APP_DOCKER_PLATFORM:-$TASK_HOST_ARCH}
case "$TASK_EXPECTED" in arm64|amd64) : ;; *) fail 'APP_DOCKER_PLATFORM 只接受 arm64 或 amd64。' ;; esac
[ "$TASK_EXPECTED" = "$TASK_HOST_ARCH" ] || fail '指定平台与宿主机架构不同，拒绝依赖模拟器启动。'

# This check MUST precede every docker run. Missing images never fall through
# to a run-by-tag that would implicitly attempt an Internet pull.
TASK_IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$TASK_IMAGE" 2>/dev/null) || fail "本地没有镜像 $TASK_IMAGE；请先 docker load -i 离线镜像文件。不会尝试联网拉取。"
TASK_IMAGE_PLATFORM=$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$TASK_IMAGE_ID" 2>/dev/null) || fail '无法读取本地镜像平台。'
[ "$TASK_IMAGE_PLATFORM" = "linux/$TASK_EXPECTED" ] || fail "镜像平台 $TASK_IMAGE_PLATFORM 与宿主机 linux/$TASK_EXPECTED 不符。"

for TASK_CONTAINER in "$TASK_WEB" "$TASK_MONITOR"; do
    if docker container inspect "$TASK_CONTAINER" >/dev/null 2>&1; then
        fail "已存在容器 $TASK_CONTAINER，未作覆盖。需重建时先运行 docker-down.sh；数据卷会保留。"
    fi
done

if docker volume inspect "$TASK_VOLUME" >/dev/null 2>&1; then
    TASK_OWNER=$(docker volume inspect --format '{{index .Labels "org.asset-console.managed"}}' "$TASK_VOLUME" 2>/dev/null) || fail '无法核对数据卷标记。'
    [ "$TASK_OWNER" = true ] || fail "已存在未标记的数据卷 $TASK_VOLUME，拒绝擅自使用或覆盖；请指定新的 APP_DATA_VOLUME。"
else
    docker volume create --label org.asset-console.managed=true "$TASK_VOLUME" >/dev/null
fi

trap cleanup_failed_start EXIT
trap 'exit 1' HUP INT TERM

TASK_ATTEMPTED_WEB=1
docker run -d --name "$TASK_WEB" \
    --label org.asset-console.managed=true --label org.asset-console.role=web \
    --label "org.asset-console.instance=$TASK_INSTANCE" \
    --restart unless-stopped --network host --user 10001:10001 \
    --cap-drop ALL --security-opt no-new-privileges \
    --env-file "$TASK_ENV" -e APP_DATA_DIR=/data -e APP_BIND=0.0.0.0 -e "APP_INSTANCE_ID=$TASK_INSTANCE" \
    -v "$TASK_VOLUME:/data" "$TASK_IMAGE_ID" web >/dev/null

TASK_READY=0
TASK_ATTEMPT=0
while [ "$TASK_ATTEMPT" -lt 60 ]; do
    if docker exec "$TASK_WEB" python -c 'import json,os,urllib.request; u="http://127.0.0.1:"+os.environ.get("APP_PORT","8000")+"/health/"; r=urllib.request.build_opener(urllib.request.ProxyHandler({})).open(u,timeout=2); d=json.load(r); expected=os.environ.get("APP_INSTANCE_ID"); assert expected and d["status"]=="ok" and d.get("instance_id")==expected' >/dev/null 2>&1; then
        TASK_READY=1
        break
    fi
    TASK_ATTEMPT=$((TASK_ATTEMPT + 1))
    sleep 1
done
if [ "$TASK_READY" -ne 1 ]; then
    docker logs --tail 60 "$TASK_WEB" >&2 || :
    fail 'Web 服务在等待期内未就绪，请检查日志、端口冲突、允许的主机名及数据卷权限。'
fi

TASK_ATTEMPTED_MONITOR=1
docker run -d --name "$TASK_MONITOR" \
    --label org.asset-console.managed=true --label org.asset-console.role=monitor \
    --label "org.asset-console.instance=$TASK_INSTANCE" \
    --restart unless-stopped --network host --user 10001:10001 --no-healthcheck \
    --cap-drop ALL --cap-add NET_RAW \
    --env-file "$TASK_ENV" -e APP_DATA_DIR=/data \
    -v "$TASK_VOLUME:/data" "$TASK_IMAGE_ID" monitor >/dev/null

printf '%s\n' 'Web 已就绪，检测容器已启动。请检查检测容器日志确认 ICMP 权限及内网连通性。'
printf '数据卷：%s（停机和重建容器均保留）\n' "$TASK_VOLUME"
printf '首次创建管理员：docker exec -it %s python manage.py init_admin\n' "$TASK_WEB"
printf '查看日志：docker logs --tail 100 %s\n' "$TASK_MONITOR"
