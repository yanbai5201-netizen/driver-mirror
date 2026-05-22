@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ========================================
echo  driver-mirror 本地维护目录
echo  GitHub: yanbai5201-netizen/driver-mirror
echo ========================================
echo.
echo 本目录作用：
echo   packages\*.zip     本地打包（不要 git commit）
echo   manifest.json      推送到 GitHub main 分支
echo   upload_release.py  上传 zip 到 GitHub Release
echo.
echo [1] 推送 manifest.json 到 GitHub
git add manifest.json README.md .gitignore upload_release.py
git -c user.email=yanbai5201-netizen@users.noreply.github.com -c user.name=yanbai5201-netizen commit -m "Update manifest" 2>nul
git push origin main
echo.
echo [2] 上传 packages 到 Release（需已登录 git 凭据）
python upload_release.py
echo.
pause
