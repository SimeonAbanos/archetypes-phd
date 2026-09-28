@echo off
rem Steps 1 and 2 - structural, then semantic validity of every instance.
rem Runs validate.ps1 from this folder. The window stays open until Enter is pressed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate.ps1"
if errorlevel 1 pause
