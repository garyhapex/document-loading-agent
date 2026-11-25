@echo off
REM ==========================================================================
REM  Setup-DLA-Relay.cmd   -   Document Loading Agent invoice relay setup
REM
REM  Double-click this file. It runs Setup-DLA-Relay.ps1 (same folder), which
REM  asks Windows for administrator rights, asks for DEV or PRD, the database
REM  address and the relay token, checks them with the database, and installs
REM  the relay as its own Windows service, e.g. "DLA Invoice Relay PRD".
REM
REM  To remove a relay:   Setup-DLA-Relay.cmd /uninstall
REM
REM  Author : Claude for Gary D. Hall, 11/24/2026 (same pattern as the
REM           Stick-IT relay setup)
REM ==========================================================================
setlocal
set MODE=
if /I "%~1"=="/uninstall" set MODE=-Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-DLA-Relay.ps1" %MODE%
endlocal
