# Generated at plugin render time. Dot-sourced by start-monk-agent.ps1 so the
# agent (and the launcher telemetry beacon) can report the real plugin version
# in telemetry (MONK_PLUGIN_VERSION). Sets the process env var so the value both
# is readable here and is inherited by the spawned agent — the PowerShell
# counterpart of plugin-version.sh.
$env:MONK_PLUGIN_VERSION = "0.1.49"
