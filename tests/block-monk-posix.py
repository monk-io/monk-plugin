#!/usr/bin/env python3
import json
import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MISSING_AGENT = str(REPO_ROOT / ".missing-monk-agent-for-posix-test")

CASES = [
    ("direct", "monk status", True),
    ("double_quoted", '"monk" status', True),
    ("single_quoted", "'monk' status", True),
    ("backslash_escaped", r"\monk status", True),
    ("sudo_quoted", 'sudo "monk" deploy', True),
    ("command_wrapper", "command monk deploy", True),
    ("env_wrapper", "env FOO=bar monk deploy", True),
    ("separator", "echo ok; monk deploy", True),
    ("similar_command", "monkey deploy", False),
    ("harmless_argument", "grep monk README.md", False),
    ("quoted_argument", 'grep "monk" README.md', False),
]

HOOKS = [
    ("hooks/block-monk.sh", "claude"),
    ("plugins/monk/hooks/block-monk.sh", "claude"),
    (".antigravity-plugin/hooks/block-monk.sh", "antigravity"),
]


def payload_for(format_name, command):
    if format_name == "claude":
        return json.dumps({"tool_input": {"command": command}})
    return json.dumps({"toolCall": {"name": "run_command", "args": {"CommandLine": command}}})


def denied_by_output(format_name, output):
    if format_name == "claude":
        return '"permissionDecision"' in output and '"deny"' in output
    return '"decision"' in output and '"deny"' in output


def main():
    env = os.environ.copy()
    env["MONK_AGENT_PATH"] = MISSING_AGENT

    for hook, format_name in HOOKS:
        for name, command, expected in CASES:
            proc = subprocess.run(
                [str(REPO_ROOT / hook)],
                input=payload_for(format_name, command),
                text=True,
                capture_output=True,
                env=env,
                check=False,
            )
            denied = denied_by_output(format_name, proc.stdout)
            if denied != expected:
                raise AssertionError(
                    f"{hook} case {name!r} expected denied={expected}, got denied={denied}; "
                    f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
                )

    print("POSIX block-monk fallback tests passed.")


if __name__ == "__main__":
    main()
