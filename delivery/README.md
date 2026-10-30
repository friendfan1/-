# 信息化资产管理系统：ARM64 Docker 离线部署包 V1.2

V1.2 新增 **Excel 批量导入、模板下载、上传预览、逐行校验和导入日志**。目标为统信 UOS ARM64；沿用已正常运行的 Docker 环境，宿主机无需 Python 和网络。

- [下载最新完整部署包 V1.2（约 49 MB）](https://github.com/friendfan1/-/raw/refs/heads/main/delivery/asset-console-docker-1.2-arm64-offline.tar.gz)
- [下载 SHA256 校验文件](https://github.com/friendfan1/-/raw/refs/heads/main/delivery/asset-console-docker-1.2-arm64-offline.tar.gz.sha256)
- [直接下载 Excel 导入模板](https://github.com/friendfan1/-/raw/refs/heads/main/delivery/asset-import-template.xlsx)
- [已部署 V1.1：离线升级步骤](V1.2离线升级步骤.md)
- [Excel 批量导入使用说明](Excel批量导入使用说明.md)
- [V1.2 验证报告](V1.2验证报告.md)

仓库为私有时，请先在浏览器登录有权访问的 GitHub 账号。若显示文件页，点击 Download raw file。

## 已部署用户升级

请先阅读上面的「V1.2 离线升级步骤」。先备份，再复制原 `deploy/docker.env` 到新目录，导入新镜像并用新包里的脚本重建两个容器。继续使用 **原数据卷 `asset-console-data`**，保留资产、账号、日志和密钥；使用原账号登录。包内也提供完整的升级说明和 Excel 模板。

新版本镜像标签为 `asset-console:1.2-arm64`。不要直接拿外层交付包执行 `docker load`；先解压，再导入里面的 `asset-console-1.2-arm64.image.tar.gz`。

## 新功能怎么用

维护员登录后，点击「资产台账 → 批量导入 → 下载 Excel 模板」。在「资产导入」表填写设备，上传预览，通过检查后确认入库。

- 同一表可填写工作网终端、互联网终端、打印机。
- 资产类别、部门、使用人、安装位置必填；其他信息可以后续补充。
- 仅支持 `.xlsx`，每批最多 200 条，文件不超过 5 MB。
- 模板数据区为空，电话、房间号、序列号等设置为文本。参考示例位于说明页，不会自动导入。
- 本功能新增资产；已有资产通过台账编辑。重复序列号、MAC、同类网络 IP 或整行资料会阻止整批导入，并显示 Excel 行号。
- 一次确认全部保存或全部撤销；逐台记录新增字段、来源 IP、账号、文件、行号和批次。导出继续显示每台资产最后更新时间。
- 查看、导出和模板下载免登录；导入和维护需要登录。

## 完整包校验

文件大小：51,058,574 字节。SHA256：

```text
f7a5163344adafd366c25f3759d93e0381a7e5e66a5a314a395a0f89ad66eff3
```

```sh
sha256sum -c asset-console-docker-1.2-arm64-offline.tar.gz.sha256
```

## 首次部署

```sh
tar -xzf asset-console-docker-1.2-arm64-offline.tar.gz
cd asset-console-docker-1.2-arm64-offline
docker load -i asset-console-1.2-arm64.image.tar.gz
cp deploy/docker.env.example deploy/docker.env
chmod 600 deploy/docker.env
```

将 `deploy/docker.env` 中的示例 IP 改为实际服务器内网 IP，再执行：

```sh
sh deploy/docker-up.sh
docker exec -it asset-console-web python manage.py init_admin
```

首次部署没有默认管理员或单位资产。完整部署、备份恢复及运行状态说明见包内 `docs/Docker离线部署指南.md`。

## 验证与历史故障排查

已通过 69 项应用测试（含 ARM64 模拟容器）、真实 Chrome 83 的 36 项浏览器检查、13 项实际下载文件内容检查及 11 项容器升级断言。云端 daemon 为 Docker 28.4.0，实际 UOS 上的 V1.2 升级和工作网 Ping 仍须现场核对，详见验证报告。

若仍使用旧 Docker 18 并遇到 net_prio 错误，历史资料见 [net_prio 故障排查](故障排查-net_prio.md)。此前单独的 `docker-up.sh` 和修复小包属于 V1.1 历史补丁；V1.2 升级使用完整新包中的脚本。
