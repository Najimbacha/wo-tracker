@echo off
rem Builds the app (Windows). All output goes to build-log.txt.
rem Uses its own Flutter 3.47.7 in C:\src\flutter-3.47 so your other Flutter (C:\src\flutter)
rem and your other projects are not changed.
cd /d "%~dp0"
set FL=C:\src\flutter-3.47
echo Building WO Tracker... this window closes when done.
echo The first time it also downloads Flutter 3.47 (about 1 GB), so allow 20-40 minutes.
(
echo == Preparing Flutter 3.47.7 in %FL%
if not exist "%FL%\bin\flutter.bat" git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git "%FL%"
) > "%~dp0build-log.txt" 2>&1
set PATH=%FL%\bin;%PATH%
call flutter --disable-analytics >> "%~dp0build-log.txt" 2>&1
call flutter config --no-cli-animations >> "%~dp0build-log.txt" 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-app.ps1" %* >> "%~dp0build-log.txt" 2>&1
echo exit code %errorlevel% >> "%~dp0build-log.txt"
echo BUILD-FINISHED >> "%~dp0build-log.txt"
