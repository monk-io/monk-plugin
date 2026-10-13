@echo off
rem Windows half of scripts/monk-mcp: Claude Code's `monk` MCP server, which is
rem monk-agent's stdio bridge. Claude Code resolves the extensionless `monk-mcp`
rem in the plugin manifest to this file. stdout carries MCP protocol only.
rem
rem The bridge runs straight from cmd, not under PowerShell: a native command
rem started from a PowerShell script has its stdout read and re-written by
rem PowerShell, which an MCP stream doesn't survive. No labels either: this file
rem ships with LF line endings, which cmd's goto can misread.
setlocal
set "AGENT=%MONK_AGENT_PATH%"
if not defined AGENT if defined MONK_AGENT_INSTALL_DIR set "AGENT=%MONK_AGENT_INSTALL_DIR%\monk-agent.exe"
if not defined AGENT set "AGENT=%USERPROFILE%\.monk\bin\monk-agent.exe"
rem No binary yet: install it. Updating stays with the SessionStart hook, which
rem restarts the agent after an update. The installer prints the path last.
rem Pinned to the absolute Windows PowerShell (ENG-441), see run-powershell.cmd.
if not defined MONK_AGENT_PATH if not exist "%AGENT%" if not "%MONK_AGENT_SKIP_ENSURE%"=="1" for /f "usebackq delims=" %%P in (`""%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ensure-monk-agent.ps1""`) do set "AGENT=%%P"
rem One-line ifs, not a ( ) block: a path like "Program Files (x86)" ends a block early.
if not exist "%AGENT%" echo monk-agent was not found at "%AGENT%" 1>&2
if not exist "%AGENT%" exit /b 2
"%AGENT%" mcp-stdio
exit /b %ERRORLEVEL%
