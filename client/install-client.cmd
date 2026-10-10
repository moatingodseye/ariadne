@echo off
setlocal enabledelayedexpansion
rem Ariadne client installer (Windows): ariadne_cli.exe (the command line) and
rem ariadne_mcp.exe (the MCP server) - two executables, one per job.
rem
rem   install-client.cmd http://ariadne-host:8193 [install-dir]
rem
rem The URL is REQUIRED and that is deliberate. Unconfigured, the exe tries
rem http://localhost:8193, which is right only on the server box itself; a client
rem installed without being pointed somewhere would talk to whatever answers
rem there. This script never leaves that to chance.

if "%~1"=="" goto :usage
set "ARIADNE_URL=%~1"
set "TARGET=%~2"
rem One flat, findable tool folder - D:\tool where there is a D: drive.
if "%TARGET%"=="" if exist D:\ set "TARGET=D:\tool"
if "%TARGET%"=="" set "TARGET=C:\tool"

echo(
echo Installing the Ariadne client
echo   server : %ARIADNE_URL%
echo   folder : %TARGET%
echo(

if not exist "%TARGET%" mkdir "%TARGET%" || goto :nodir
copy /Y "%~dp0ariadne_cli.exe" "%TARGET%\ariadne_cli.exe" >nul || goto :nocopy
echo   copied ariadne_cli.exe
copy /Y "%~dp0ariadne_mcp.exe" "%TARGET%\ariadne_mcp.exe" >nul || goto :nocopy
echo   copied ariadne_mcp.exe

rem A USER environment variable, not a system one: this needs no elevation and
rem it is the account that runs the CLI that has to see it.
setx ARIADNE_API_URL "%ARIADNE_URL%" >nul
echo   set ARIADNE_API_URL (new shells only - this one still has the old value)
echo(

rem The flag goes AFTER the command. `ariadne --url=... listprojects` is read as
rem an op called "--url=..." and refused — found by running this, not by reading it.
"%TARGET%\ariadne_cli.exe" listprojects --url=%ARIADNE_URL%
if errorlevel 1 (
  echo(
  echo   ^>^> the server did not answer. Check the URL and that :8193 is reachable.
) else (
  echo(
  echo   ^>^> the server answered, so the client is working.
)

echo(
echo Register it with Claude as an MCP server:
echo(
echo   claude mcp add ariadne -- "%TARGET%\ariadne_mcp.exe" --url=%ARIADNE_URL%
echo(
echo The --url is repeated there on purpose: an MCP server is started by another
echo process, which may not have inherited ARIADNE_API_URL.
exit /b 0

:usage
echo Usage: install-client.cmd ^<server-url^> [install-dir]
echo   e.g. install-client.cmd http://ariadne:8193
echo        install-client.cmd http://ariadne:8193 E:\tool
echo   The folder defaults to D:\tool, or C:\tool where there is no D: drive.
exit /b 1
:nodir
echo FAILED: could not create %TARGET%
exit /b 2
:nocopy
echo FAILED: could not copy ariadne_cli.exe / ariadne_mcp.exe into %TARGET%
exit /b 3
