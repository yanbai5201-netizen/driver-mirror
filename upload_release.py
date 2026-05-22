# -*- coding: utf-8 -*-
"""一次性脚本：用 git 凭据创建 GitHub Release 并上传驱动 zip。"""
from __future__ import annotations

import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = "yanbai5201-netizen/driver-mirror"
TAG = "v2026.05.22"
TITLE = "v2026.05.22"
NOTES = "Intel Chipset / Serial IO / Bluetooth driver packages"
ROOT = Path(__file__).resolve().parent
ASSETS = [
    ROOT / "packages" / "intel_chipset.zip",
    ROOT / "packages" / "intel_serialio.zip",
    ROOT / "packages" / "intel_bluetooth.zip",
]


def _git_token() -> str:
    proc = subprocess.run(
        ["git", "credential", "fill"],
        input="protocol=https\nhost=github.com\n\n",
        capture_output=True,
        text=True,
        timeout=15,
    )
    token = ""
    for line in proc.stdout.splitlines():
        if line.startswith("password="):
            token = line.split("=", 1)[1].strip()
    if not token:
        raise RuntimeError("无法从 git 凭据获取 GitHub Token，请运行 gh auth login")
    return token


def _api_request(method: str, url: str, token: str, data: bytes | None = None, headers: dict | None = None) -> bytes:
    req_headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "driver-mirror-uploader",
    }
    if headers:
        req_headers.update(headers)
    request = urllib.request.Request(url, data=data, method=method, headers=req_headers)
    with urllib.request.urlopen(request, timeout=300) as response:
        return response.read()


def _get_release(token: str) -> dict | None:
    url = f"https://api.github.com/repos/{REPO}/releases/tags/{TAG}"
    try:
        body = _api_request("GET", url, token)
        return json.loads(body.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise


def _create_release(token: str) -> dict:
    payload = json.dumps(
        {"tag_name": TAG, "name": TITLE, "body": NOTES, "draft": False, "prerelease": False}
    ).encode("utf-8")
    url = f"https://api.github.com/repos/{REPO}/releases"
    body = _api_request(
        "POST",
        url,
        token,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    return json.loads(body.decode("utf-8"))


def _upload_asset(token: str, upload_url: str, asset_path: Path) -> None:
    upload_url = upload_url.replace("{?name,label}", f"?name={asset_path.name}")
    data = asset_path.read_bytes()
    _api_request(
        "POST",
        upload_url,
        token,
        data=data,
        headers={
            "Content-Type": "application/octet-stream",
            "Content-Length": str(len(data)),
        },
    )


def main() -> int:
    for asset in ASSETS:
        if not asset.is_file():
            print(f"缺少文件：{asset}", file=sys.stderr)
            return 1

    token = _git_token()
    release = _get_release(token)
    if release is None:
        print("正在创建 Release…")
        release = _create_release(token)
    else:
        print(f"Release 已存在：{release.get('html_url', TAG)}")

    upload_url = str(release.get("upload_url") or "")
    if not upload_url:
        raise RuntimeError("无法获取 upload_url")

    existing = {item.get("name") for item in release.get("assets", [])}
    for asset in ASSETS:
        if asset.name in existing:
            print(f"跳过（已存在）：{asset.name}")
            continue
        print(f"正在上传：{asset.name} ({asset.stat().st_size // 1024} KB)…")
        _upload_asset(token, upload_url, asset)
        print(f"已上传：{asset.name}")

    print(f"完成：{release.get('html_url', f'https://github.com/{REPO}/releases/tag/{TAG}')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
