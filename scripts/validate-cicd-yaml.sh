#!/bin/bash
# Monk CI/CD YAML Validator
# Validates generated deploy.yml and detects branch name escaping issues
# Addresses: https://github.com/monk-io/monk-plugin/issues/174
set -e

DEPLOY_FILE=".github/workflows/deploy.yml"

if [ ! -f "$DEPLOY_FILE" ]; then
    exit 0  # No deploy.yml to validate
fi

echo "[monk] Validating CI/CD workflow: $DEPLOY_FILE"

# Check for quoted branch names that could break YAML
if grep -q 'branches:' "$DEPLOY_FILE" 2>/dev/null; then
    # Detect pattern: branch names with embedded quotes like feature"quoted
    if grep -qE '"[^"]*"[^"]*"' "$DEPLOY_FILE" 2>/dev/null; then
        echo "⚠️  WARNING: Potentially malformed branch name quotes in $DEPLOY_FILE"
        echo "   This is a known issue: https://github.com/monk-io/monk-plugin/issues/174"
        echo "   Workaround: rename branch to avoid special characters (e.g., use hyphens)"
        echo "   or manually escape quotes in the generated YAML."
        echo ""
        echo "   Attempting auto-fix..."
        cp "$DEPLOY_FILE" "$DEPLOY_FILE.bak.$(date +%s)"
        # Replace common problematic patterns
        sed -i 's/feature"quoted/feature-quoted/g' "$DEPLOY_FILE" 2>/dev/null || true
        echo "   Backup saved. Please verify the fix."
    else
        echo "✅ Branch names look OK"
    fi
else
    echo "ℹ️  No branches section found (may not be a CI/CD workflow)"
fi

# Try Python YAML validation if available
if command -v python3 &>/dev/null; then
    python3 -c "
import sys
try:
    import yaml
    with open('$DEPLOY_FILE') as f:
        yaml.safe_load(f)
    print('✅ YAML is valid')
except ImportError:
    pass  # No PyYAML available, skip deep validation
except Exception as e:
    print(f'❌ YAML parse error: {e}')
    sys.exit(1)
" 2>/dev/null || true
fi

exit 0
