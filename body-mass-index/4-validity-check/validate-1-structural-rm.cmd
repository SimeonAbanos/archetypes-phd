@echo off
rem Step 1 - structural validity: every instance against the Reference Model (RM).
rem Runs validate.ps1 from this folder. The window stays open until Enter is pressed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate.ps1" -Step 1
if errorlevel 1 pause
