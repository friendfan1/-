#!/bin/sh
# Temporary, guarded compatibility cleanup for the observed UOS 20 / Docker 18
# layout. No Docker restart, controller unmount, boot setting, or volume change.
set -eu
TASK_MODE=${1:---check}
case "$TASK_MODE" in --check|--apply) : ;; *) printf '%s\n' '用法：sudo sh fix-net-prio.sh --check 或 --apply' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || { printf '%s\n' '参数过多。' >&2; exit 2; }
TASK_ROOT=/sys/fs/cgroup
TASK_TARGET="$TASK_ROOT/net_prio"
TASK_GROUPS=/proc/cgroups
TASK_SELF=/proc/self/cgroup
TASK_MOUNTS=/proc/mounts
TASK_RESTORE_RO=0
TASK_ORIGINAL_OPTIONS=

fail() { printf '未执行清理：%s\n' "$*" >&2; exit 1; }

probe_flag() {
    TASK_PROBE_EXIT=0
    "$@" || TASK_PROBE_EXIT=$?
    case "$TASK_PROBE_EXIT" in
        0) return 0 ;;
        1) return 1 ;;
        *) fail '读取控制器或挂载信息失败，停止操作。' ;;
    esac
}

controller_present() {
    probe_flag awk '$1 == "net_prio" { found = 1 } END { exit !found }' "$TASK_GROUPS"
}

self_uses_controller() {
    probe_flag awk -F: '{ n = split($2, names, ","); for (i = 1; i <= n; i++) if (names[i] == "net_prio") found = 1 } END { exit !found }' "$TASK_SELF"
}

target_mounted() {
    probe_flag awk -v target="$TASK_TARGET" '$2 == target { found = 1 } END { exit !found }' "$TASK_MOUNTS"
}

root_options() {
    awk -v root="$TASK_ROOT" '$2 == root { print $4; exit }' "$TASK_MOUNTS"
}

restore_root() {
    TASK_EXIT=$?
    trap - EXIT HUP INT TERM
    if [ "$TASK_RESTORE_RO" -eq 1 ]; then
        TASK_NOW=$(root_options) || TASK_NOW=
        case ",$TASK_NOW," in
            *,ro,*) : ;;
            *)
                if ! mount -o "remount,$TASK_ORIGINAL_OPTIONS" "$TASK_ROOT"; then
                    printf '%s\n' '错误：未能恢复 cgroup 根目录的原只读状态。请由管理员执行：' >&2
                    printf 'mount -o "remount,%s" %s\n' "$TASK_ORIGINAL_OPTIONS" "$TASK_ROOT" >&2
                    TASK_EXIT=1
                else
                    printf '%s\n' '已恢复 cgroup 根目录的原只读挂载状态。'
                fi
                ;;
        esac
    fi
    exit "$TASK_EXIT"
}

[ "$(id -u)" -eq 0 ] || fail '请通过 sudo 或 root 执行。'
for TASK_COMMAND in awk find mount rmdir; do
    command -v "$TASK_COMMAND" >/dev/null 2>&1 || fail "缺少系统命令 $TASK_COMMAND。"
done
for TASK_FILE in "$TASK_GROUPS" "$TASK_SELF" "$TASK_MOUNTS"; do
    [ -r "$TASK_FILE" ] || fail "无法读取 $TASK_FILE。"
done
TASK_ROOT_COUNT=$(awk -v root="$TASK_ROOT" '$2 == root { n++ } END { print n+0 }' "$TASK_MOUNTS")
[ "$TASK_ROOT_COUNT" -eq 1 ] || fail 'cgroup 根目录挂载记录不唯一，需要人工核对。'
TASK_ROOT_TYPE=$(awk -v root="$TASK_ROOT" '$2 == root { print $3; exit }' "$TASK_MOUNTS")
[ "$TASK_ROOT_TYPE" = tmpfs ] || fail '此脚本只适用于截图中的 tmpfs + cgroup v1／混合布局。'
awk -v root="$TASK_ROOT/" '$3 == "cgroup" && index($2, root) == 1 && ("," $4 ",") ~ /,devices,/ { found = 1 } END { exit !found }' "$TASK_MOUNTS" || fail '未发现 cgroup v1 devices 挂载，不适用此兼容清理。'
if controller_present; then fail '内核已列出 net_prio 控制器，应排查挂载配置，不能删除目录。'; fi
if self_uses_controller; then fail '当前进程使用 net_prio 控制器，不能删除目录。'; fi
if target_mounted; then fail 'net_prio 是挂载点，不能删除目录。'; fi
if [ -L "$TASK_TARGET" ]; then fail 'net_prio 是符号链接，需要核对链接目标。'; fi
if [ ! -e "$TASK_TARGET" ]; then
    printf '%s\n' 'net_prio 目录不存在，未作修改。如 Docker 仍报相同错误，需核对 Docker 服务的挂载命名空间。'
    exit 0
fi
[ -d "$TASK_TARGET" ] || fail 'net_prio 路径不是普通目录。'
TASK_CONTENTS=$(find "$TASK_TARGET" -mindepth 1 -maxdepth 1 -print -quit) || fail '无法检查目录内容。'
[ -z "$TASK_CONTENTS" ] || fail 'net_prio 目录非空，不能进行此清理。'
TASK_ORIGINAL_OPTIONS=$(root_options)
[ -n "$TASK_ORIGINAL_OPTIONS" ] || fail '无法确认 cgroup 根目录挂载选项。'
printf '%s\n' '检查符合：内核和进程未使用 net_prio，路径未挂载、不是链接且目录为空。'
printf '原 cgroup 根目录选项：%s\n' "$TASK_ORIGINAL_OPTIONS"
if [ "$TASK_MODE" = --check ]; then
    printf '%s\n' '本次仅检查。可执行 sudo sh fix-net-prio.sh --apply 清理这个空目录。'
    exit 0
fi
trap restore_root EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
case ",$TASK_ORIGINAL_OPTIONS," in
    *,ro,*)
        # Arm restoration before remount, including interruption immediately
        # after a successful syscall. Preserve all original mount options.
        TASK_RESTORE_RO=1
        TASK_WRITABLE_OPTIONS=$(printf '%s\n' "$TASK_ORIGINAL_OPTIONS" | awk -F, '{ for (i=1; i<=NF; i++) { if ($i == "ro") $i="rw"; printf "%s%s", (i>1 ? "," : ""), $i } printf "\n" }')
        mount -o "remount,$TASK_WRITABLE_OPTIONS" "$TASK_ROOT" || fail '无法临时将 cgroup 根目录设为可写。'
        ;;
esac
# Check again before the atomic empty-directory removal; a nonempty or newly
# mounted directory will fail closed. Never use rm -rf or unmount a controller.
if controller_present || self_uses_controller || target_mounted || [ -L "$TASK_TARGET" ]; then
    fail '检查后控制器状态发生变化，已停止。'
fi
rmdir "$TASK_TARGET" || fail '空目录移除失败，保留现场并恢复原挂载状态。'
printf '%s\n' '已移除未启用控制器对应的 net_prio 空目录；结束时保留或恢复原挂载状态。'
