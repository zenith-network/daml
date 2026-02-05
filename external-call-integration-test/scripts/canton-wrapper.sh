#!/bin/bash
#
# Canton Wrapper Script
#
# Runs Canton from the canton repo using sbt.
# This is needed because the canton in the daml SDK doesn't have external call runtime support yet.
#
# Usage:
#   ./canton-wrapper.sh run -c config.conf script.canton
#   CANTON_CMD=./scripts/canton-wrapper.sh ./run_test.sh

set -e

# Find the canton repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(dirname "$SCRIPT_DIR")"
DAML_REPO="$(dirname "$TEST_DIR")"
CANTON_REPO="$(dirname "$DAML_REPO")/canton"

if [ ! -d "$CANTON_REPO" ]; then
    echo "ERROR: Canton repo not found at $CANTON_REPO"
    echo ""
    echo "Expected directory structure:"
    echo "  \$HOME/Code/canton/"
    echo "  ├── canton/     # Canton repo with external call runtime"
    echo "  └── daml/       # Daml repo"
    exit 1
fi

# Change to canton repo and run via sbt
cd "$CANTON_REPO"

# Pass all arguments to sbt run
# Convert arguments to sbt format: sbt "project community-app" "run arg1 arg2 ..."
ARGS="$@"

# Build the sbt command
# Note: We need to escape the arguments properly for sbt
exec sbt --batch "project community-app" "run $ARGS"
