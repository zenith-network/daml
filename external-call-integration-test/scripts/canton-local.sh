#!/bin/bash
#
# Run Canton from the local canton repo build
#
# This script runs Canton using the assembled JAR from the canton repo.
# Use this for integration tests when the daml SDK canton doesn't have
# external call support yet.
#
# Usage:
#   ./canton-local.sh run -c config.conf script.canton
#   CANTON_CMD=./scripts/canton-local.sh ./run_test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANTON_REPO="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/canton"
CANTON_JAR="$CANTON_REPO/community/app/target/scala-2.13/canton-open-source-3.5.0-SNAPSHOT.jar"

if [ ! -f "$CANTON_JAR" ]; then
    echo "ERROR: Canton JAR not found at $CANTON_JAR"
    echo ""
    echo "Build it with:"
    echo "  cd $CANTON_REPO"
    echo "  export PATH=\"\$HOME/.dpm/bin:\$PATH\""
    echo "  sbt 'project community-app' 'assembly'"
    exit 1
fi

# Run Canton with the assembled JAR
exec java -jar "$CANTON_JAR" "$@"
