@echo off
REM Turn the Projet R database ON (on-demand, no Windows service).
title Projet R - Start Database
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0database\start-db.ps1"
timeout /t 3 /nobreak >nul
