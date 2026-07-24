@echo off
rem Pin to the absolute Windows PowerShell path: a bare `powershell.exe` is
rem resolved with the current directory searched before PATH, so a workspace
rem could plant its own. %SystemRoot% is OS-controlled and non-writable. (ENG-441)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-monk-agent.ps1" %*
