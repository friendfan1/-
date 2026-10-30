# 部署错误：unable to find net_prio in controller set

这条错误来自 Docker/containerd 读取 Linux cgroup 控制器路径的阶段，不表示需要重新构建 Python 应用。旧版 containerd 1.2.2 的 cgroups 路径实现会在进程控制器表里找不到 net_prio 时产生此错误，相关文件系统目录／挂载和实际启用的控制器可能不一致。不能只凭这一行确定为 cgroup v2，也不应直接修改引导参数或重启宿主机。

## 收集只读诊断

在目标 UOS 上执行并保留完整输出：

```sh
docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}'
docker info --format 'OS={{.OperatingSystem}} Kernel={{.KernelVersion}} Arch={{.Architecture}} CgroupDriver={{.CgroupDriver}}'
stat -fc %T /sys/fs/cgroup
cat /proc/cgroups
sed -n '/cgroup/p' /proc/mounts
```

需要时进一步核对进程自身控制器和目录：

```sh
cat /proc/self/cgroup
ls -ld /sys/fs/cgroup/net_prio /sys/fs/cgroup/net_cls*
```

需根据这些结果区分控制器缺失、挂载／目录不一致、混合 cgroup 和纯 v2 模式，再给匹配 UOS 的处理步骤。宿主的 cgroup 配置无法由业务容器镜像自动修复。

## 启动脚本补丁

本目录另有修订后的 `docker-up.sh` 和校验文件。它改进了失败清理：当 docker run 创建了容器但启动失败时，按本次调用的唯一标签清理残留容器；不删除数据卷，也不清理其他调用创建的容器。

此补丁**不修复宿主 net_prio 配置**，不需要重新导入镜像。需要使用时，将它替换到解压后的 `deploy/docker-up.sh`；先完成主机诊断与对应修复，再重新启动。原包已留下的失败容器可通过包内 `deploy/docker-down.sh` 按系统标签清理，脚本会保留数据卷。

维护来源：
- https://github.com/containerd/containerd/blob/v1.2.2/vendor/github.com/containerd/cgroups/paths.go
- https://github.com/containerd/containerd/blob/v1.2.2/vendor/github.com/containerd/cgroups/v1.go

修订脚本已通过14项启停及入口模拟测试，包含容器创建失败、monitor失败及并发创建时不误删其他实例；这不是目标 UOS 主机修复验证。
