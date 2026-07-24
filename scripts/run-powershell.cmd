@echo off
rem ENG-441 shim: launch Windows PowerShell from an absolute, OS-controlled path.
rem
rem Host hook runners do NOT reliably expand %SystemRoot% (or ${SystemRoot} /
rem $SystemRoot) inside the hook JSON command string - Claude Code, verified,
rem leaves it literal - so an inline "%SystemRoot%\...\powershell.exe" fails to
rem resolve and the hook silently no-ops. This .cmd is instead executed by
rem cmd.exe, where %SystemRoot% DOES expand to a non-writable location, so the pin
rem stays correct AND robust to a non-standard system root. A bare `powershell.exe`
rem would be resolved via the current directory before PATH, letting a planted
rem binary hijack the hook; an absolute path defeats that.
rem
rem The first argument is the .ps1 to run; any remaining arguments are forwarded.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File %*
