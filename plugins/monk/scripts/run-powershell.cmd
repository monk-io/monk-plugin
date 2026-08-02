:; exit 0
@echo off
rem The first line is a POSIX guard, not decoration. To cmd.exe it is a label -
rem skipped, and never echoed, since label lines are not echoed even with ECHO ON
rem - while /bin/sh reads it as a no-op followed by "exit 0". It is needed because
rem Claude Code runs EVERY hook entry in a hooks.json array on every platform: it
rem has no commandWindows support at all, verified against the 2.1.220 binary, so
rem the Windows entry - this shim - is also spawned on macOS and Linux. Before the
rem guard, /bin/sh there failed with 126 "Permission denied" on a non-executable
rem .cmd and Claude Code printed a "PreToolUse:Bash hook error" banner on every
rem single Bash tool call. The shim now ships executable, so sh runs it as a
rem script and it exits 0 in silence; the sibling .sh hook entry does the real
rem work on those platforms. Keep the rest of this file sh-parseable as well - no
rem parentheses, no backticks, no unbalanced quotes - so a shell that reads ahead
rem past the exit cannot trip over the batch body. plugin/src/check.ts enforces
rem the guard line, the executable bit, and sh -n. ENG-441 follow-up.
rem
rem ENG-441 shim: launch Windows PowerShell from an absolute, OS-controlled path.
rem
rem Host hook runners do NOT reliably expand %SystemRoot% - or the shell-style
rem SystemRoot variants - inside the hook JSON command string. Claude Code,
rem verified, leaves it literal, so an inline "%SystemRoot%\...\powershell.exe"
rem fails to resolve and the hook silently no-ops. This .cmd is instead executed
rem by cmd.exe, where %SystemRoot% DOES expand to a non-writable location, so the
rem pin stays correct AND robust to a non-standard system root. A bare
rem powershell.exe would be resolved via the current directory before PATH,
rem letting a planted binary hijack the hook; an absolute path defeats that.
rem
rem The first argument is the .ps1 to run; any remaining arguments are forwarded.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File %*
