@echo off
setlocal
title Upload to GitHub
color 0B

:: ÏÅÐÅÕÎÄÈÌ Â ÏÀÏÊÓ, ÃÄÅ ËÅÆÈÒ ÝÒÎÒ ÁÀÒÍÈÊ
cd /d "%~dp0"

echo ====================================================
echo   AUTOMATIC UPLOAD TO GITHUB
echo ====================================================
echo.

where git >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo [ERROR] Git is not installed or not in PATH!
    pause
    exit /b
)

:: Ïðîâåðêà, ÷òî ìû â ïðàâèëüíîé ïàïêå
if not exist "RustOptimizer.bat" (
    color 0E
    echo [WARNING] "RustOptimizer.bat" not found in this folder!
    echo Make sure you put this script IN THE SAME FOLDER as your project files.
    echo.
    pause
)

:: Íàñòðàèâàåì Git (÷òîáû íå áûëî îøèáêè Author identity unknown)
git config --global user.name "proot9078-ux"
git config --global user.email "proot9078-ux@users.noreply.github.com"

set REPO_URL=https://github.com/proot9078-ux/Rust-Optimizer.git

echo [1/5] Initializing repository...
if not exist .git (
    git init
) else (
    echo Repository already exists, skipping.
)

echo.
echo [2/5] Adding files...
git add .

echo.
echo [3/5] Creating commit...
git commit -m "PURPLE RUSH v3.1 initial commit"

echo.
echo [4/5] Setting up branch and remote...
git branch -M main
git remote remove origin >nul 2>&1
git remote add origin %REPO_URL%

echo.
echo [5/5] Pushing to GitHub...
echo (A browser window may open - log in to your GitHub account)
echo.
git push -u origin main

if %errorlevel% equ 0 (
    color 0A
    echo.
    echo ====================================================
    echo   SUCCESS! Files uploaded to GitHub.
    echo   Check: https://github.com/proot9078-ux/Rust-Optimizer
    echo ====================================================
) else (
    color 0C
    echo.
    echo ====================================================
    echo   [ERROR] Upload failed.
    echo   Please check the errors above.
    echo ====================================================
)

echo.
pause