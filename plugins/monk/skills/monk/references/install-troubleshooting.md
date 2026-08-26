# Monk Installation Troubleshooting

This guide covers common issues during Monk installation and runtime setup.

## Ubuntu-Monk WSL Distro Stopped After Reboot

**Symptoms:**
- `wsl -l -v` shows `Ubuntu-Monk` as `Stopped`
- `netstat -an | findstr 2137` shows no listener on 127.0.0.1:2137
- Monk commands fail with `ECONNREFUSED 127.0.0.1:2137`
- Extension shows "Install Runtime" instead of recovery option

**Root Cause:**
After Windows reboot or `wsl --shutdown`, the Ubuntu-Monk distro enters `Stopped` state. The monkd daemon inside the distro is not running, so port 2137 is not accessible from Windows.

**Automatic Recovery (Recommended):**
The Monk plugin now automatically detects this state and attempts recovery:
1. Runs `wsl --shutdown` to clean up any stale state
2. Starts the Ubuntu-Monk distro
3. Waits for monkd to become available on port 2137
4. Starts monk-agent

**Manual Recovery:**
If automatic recovery fails:
```powershell
wsl --shutdown
wsl -d Ubuntu-Monk
```
Then wait 10-15 seconds for monkd to start, and retry your Monk command.

**Verification:**
```powershell
wsl -l -v
# Should show Ubuntu-Monk as Running

netstat -an | findstr 2137
# Should show TCP 127.0.0.1:2137 LISTENING
```

## Port 2137 Already in Use

**Symptoms:**
- `netstat -an | findstr 2137` shows LISTENING but Monk commands fail
- Multiple monkd instances may be running

**Resolution:**
```powershell
wsl --shutdown
wsl -d Ubuntu-Monk
```

## Monk CLI Not in PATH

**Symptoms:**
- `monk --version` returns "command not found"
- Extension cannot locate monk binary

**Resolution:**
Ensure `~/.monk/bin` is in your PATH:
```bash
echo 'export PATH="$HOME/.monk/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Authentication Issues

**Symptoms:**
- Monk commands return 401 Unauthorized
- Browser sign-in loop

**Resolution:**
1. Run `monk auth logout`
2. Run `monk auth login` and complete browser sign-in
3. Verify with `monk whoami`

## Daemon Version Mismatch

**Symptoms:**
- Extension and monkd version mismatch
- Unexpected API errors

**Resolution:**
```bash
monk update
# or reinstall runtime via extension
```

## Getting Help

If issues persist:
1. Run `Monk: Diagnostics` command in your editor
2. Check logs at `~/.monk/ensure-monk-agent.log`
3. File an issue at https://github.com/monk-io/monk-plugin/issues

Include:
- OS and version
- `monk --version` output
- Diagnostics output
- Relevant log excerpts
