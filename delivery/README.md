# 信息化资产管理系统：ARM64 Docker 离线部署包 V1.1

目标环境：统信 UOS ARM64、Docker 18.09.1（build 4c52b90）。镜像内含 Python、全部依赖、系统 Ping 与本地页面资源；宿主机无需 Python，无需联网安装或拉取镜像。

- [下载完整部署包（约49MB）](https://github.com/friendfan1/-/raw/refs/heads/main/delivery/asset-console-docker-1.1-arm64-offline.tar.gz)
- [下载 SHA256 校验文件](https://github.com/friendfan1/-/raw/refs/heads/main/delivery/asset-console-docker-1.1-arm64-offline.tar.gz.sha256)

仓库为私有时，请先在浏览器登录有权访问的 GitHub 账号。若浏览器显示文件页，点击 Download raw file。

文件大小：51,029,145 字节。SHA256：

```text
05d12c6aa5b0c1f9477af9691eec553918b823525e537f1a17e318af7c7ca485
```

## 部署

把部署包和校验文件复制到 UOS 服务器的同一目录，执行：

```sh
sha256sum -c asset-console-docker-1.1-arm64-offline.tar.gz.sha256
tar -xzf asset-console-docker-1.1-arm64-offline.tar.gz
cd asset-console-docker-1.1-arm64-offline
docker load -i asset-console-1.1-arm64.image.tar.gz
cp deploy/docker.env.example deploy/docker.env
chmod 600 deploy/docker.env
```

在 UOS 上编辑 `deploy/docker.env`，把 `APP_ALLOWED_HOSTS` 中的 `10.10.1.10` 改成服务器的实际内网 IP，保留 `127.0.0.1,localhost`。然后执行：

```sh
sh deploy/docker-up.sh
docker exec -it asset-console-web python manage.py init_admin
```

按提示创建维护管理员，然后在客户端浏览器访问服务器内网 IP 的 8000 端口。查看与导出无需登录，维护需要登录。没有默认管理员密码，也没有单位资产数据。

完整部署、备份恢复和升级说明在包内 `docs/Docker离线部署指南.md`；启停脚本保留持久数据卷。

## 验证范围

已通过 ARM64 模拟应用测试、真实 Chrome 83、容器停止、备份恢复与镜像回读校验。使用 Docker 18.09.1 客户端已导入云端 Docker 28 服务端；真实 UOS 的 Docker 18.09.1 服务端及单位工作网 Ping 仍需现场验收。详见包内验证报告。

## Docker 创建容器报 net_prio 错误

参见 [net_prio 故障排查](故障排查-net_prio.md)。本目录提供启动失败清理补丁 `docker-up.sh`，它不改变镜像或数据卷，不代替宿主 cgroup 配置修复。
