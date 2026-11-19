@echo off
rem Step 2 - semantic validity: every instance against the archetype.
rem Runs validate.ps1 from this folder. The window stays open until Enter is pressed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate.ps1" -Step 2
if errorlevel 1 pause
