@echo off
REM Turn the Projet R database OFF.
title Projet R - Stop Database
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0database\stop-db.ps1"
timeout /t 3 /nobreak >nul
