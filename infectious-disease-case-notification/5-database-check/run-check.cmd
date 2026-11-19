@echo off
rem Database check - the same notices in MariaDB or MySQL and in eXist-db.
rem Runs run-check.ps1 from this folder. Without parameters the database client is looked up,
rem the server is 127.0.0.1:3306 with the user root and no password, and eXist-db is at
rem http://localhost:8080/exist with the user admin and no password. Other values are given as
rem parameters, for example: run-check.cmd -DbPassword secret -DbPort 3307
rem The window stays open until Enter is pressed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-check.ps1" %*
pause
