# driver-mirror

驱动检测安装程序的**远程驱动镜像清单**。

- 仓库：https://github.com/yanbai5201-netizen/driver-mirror
- 程序拉取：`https://raw.githubusercontent.com/yanbai5201-netizen/driver-mirror/main/manifest.json`
- **只同步规则与下载地址**，驱动 zip 通过 GitHub Release 分发

## 目录

```
manifest.json       ← 程序同步此文件
packages/           ← 本地打包用（上传 Release 前在此准备 zip）
README.md
```

## 发新版流程

1. 更新 `packages/` 里的 zip（或从 Intel/Realtek 官网下载后重命名）
2. 计算 SHA256（PowerShell）：
   ```powershell
   Get-FileHash packages\intel_chipset.zip -Algorithm SHA256
   ```
3. 修改 `manifest.json`：`version`、`packages.*.version`、`packages.*.sha256`
4. Commit 并 push `manifest.json`
5. **Releases → New release**，Tag 如 `v2026.05.22`，上传 `packages/*.zip`
6. 用户端：驱动程序 → **更多 → 同步驱动镜像清单**

## 当前 Release v2026.05.22

| 文件 | 对应 Seed 包 | SHA256 |
|------|----------------|--------|
| intel_chipset.zip | Seed_Intel_Chipset_INF | 见 manifest.json |
| intel_serialio.zip | Seed_Intel_SerialIO | 见 manifest.json |
| intel_bluetooth.zip | Seed_Intel_Bluetooth | 见 manifest.json |

其余包 URL 已在 manifest 中预留，上传 zip 后填 `sha256` 即可。

## 注意

- 仓库需为 **Public**，否则客户端无法无 Token 拉取 manifest
- `version` 字段递增后，程序才会下载新版本
