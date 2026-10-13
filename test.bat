@echo off
rem Runs the app's automatic screen test only (a few minutes). Output goes to test-log.txt.
cd /d "%~dp0app"
echo Testing every screen of WO Tracker... this window closes when done.
set PATH=C:\src\flutter-3.47\bin;%PATH%
call flutter test test\screens_smoke_test.dart --reporter expanded > "%~dp0test-log.txt" 2>&1
echo exit code %errorlevel% >> "%~dp0test-log.txt"
echo TEST-FINISHED >> "%~dp0test-log.txt"
