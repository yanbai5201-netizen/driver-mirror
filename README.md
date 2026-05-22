# driver-mirror

驱动检测安装程序的**远程驱动镜像清单**。

- 仓库：https://github.com/yanbai5201-netizen/driver-mirror
- 程序拉取：`https://raw.githubusercontent.com/yanbai5201-netizen/driver-mirror/main/manifest.json`
- **只同步规则与下载地址**，驱动 zip 通过 GitHub Release 分发

## 目录说明（重要）

| 位置 | 内容 |
|------|------|
| **GitHub 仓库 main** | 只有 `manifest.json` + `README.md` |
| **GitHub Release** | `intel_chipset.zip` 等驱动包（大文件放这里） |
| **本机 `driver-mirror-repo/`** | 本地打包/上传用的工作目录（在驱动项目里） |

**不要把 zip 提交到 git**，zip 只上传到 Release。

本地路径：
```
c:\Users\admin\Desktop\重复文件查询\driver-mirror-repo\
  manifest.json
  README.md
  upload_release.py
  packages\intel_chipset.zip
  packages\intel_serialio.zip
  packages\intel_bluetooth.zip
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

## 当前 Release v2026.05.29（阶段 1）

| 文件 | 对应 Seed 包 | 状态 |
|------|----------------|------|
| intel_chipset.zip | Seed_Intel_Chipset_INF | 已上传 |
| intel_serialio.zip | Seed_Intel_SerialIO | 已上传 |
| intel_bluetooth.zip | Seed_Intel_Bluetooth | 已上传 |
| intel_wifi.zip | Seed_Intel_WiFi | 新增 |
| intel_mei.zip | Seed_Intel_MEI | 新增 |
| intel_rst.zip | Seed_Intel_RST | 新增 |
| realtek_lan.zip | Seed_Realtek_LAN | 新增 |
| realtek_audio.zip | Seed_Realtek_Audio | 新增 |

本地打包脚本：`build_phase1.ps1`（需联网 + 本机已安装对应驱动时可导出 MEI/LAN）

其余包 URL 已在 manifest 中预留，上传 zip 后填 `sha256` 即可。

## 注意

- 仓库需为 **Public**，否则客户端无法无 Token 拉取 manifest
- `version` 字段递增后，程序才会下载新版本
