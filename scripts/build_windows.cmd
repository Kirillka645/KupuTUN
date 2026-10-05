@echo off
rem One-click Windows release build -> buildall\windows\ (+ KupuTUN-windows-x64.zip)
rem Needs: Flutter, Go, gcc (WinLibs) and Git for Windows in PATH.
setlocal
cd /d "%~dp0\.."
set "BASH=C:\Program Files\Git\bin\bash.exe"

echo [1/4] Go core (libkuputun.dll + wintun.dll)...
"%BASH%" scripts/build_go.sh windows || goto :fail

echo [2/4] Flutter release build...
if not exist windows\runner\main.cpp (
  call flutter create --org dev.kuputun --project-name kuputun --platforms windows . || goto :fail
)
rem KupuTUN icon (exe, taskbar, window title bar)
copy /y assets\branding\app_icon.ico windows\runner\resources\app_icon.ico >nul || goto :fail
call flutter build windows --release || goto :fail

echo [3/4] Bundling native libs...
"%BASH%" scripts/bundle_native.sh windows || goto :fail

echo [4/4] Copying to buildall\windows...
if exist buildall\windows rmdir /s /q buildall\windows
mkdir buildall\windows
xcopy /e /i /q /y build\windows\x64\runner\Release buildall\windows\KupuTUN >nul || goto :fail
powershell -NoProfile -Command "Compress-Archive -Force -Path 'buildall\windows\KupuTUN' -DestinationPath 'buildall\windows\KupuTUN-windows-x64.zip'"

echo.
echo Done: buildall\windows\KupuTUN\kuputun.exe
echo TUN mode requires "Run as administrator".
exit /b 0

:fail
echo BUILD FAILED (see errors above)
exit /b 1
