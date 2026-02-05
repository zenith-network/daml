#!/bin/bash
#
# External Call Integration Test Setup
#
# This script sets up everything needed to run the external call integration tests.
# It builds the daml compiler with external call support and the canton runtime.
#
# Prerequisites:
#   - Nix dev-env (for building daml SDK)
#   - sbt (for building canton)
#   - Python 3 (for mock service)
#
# Directory structure expected:
#   /home/user/Code/canton/
#   ├── canton/     # Canton repo with external call runtime
#   └── daml/       # Daml repo with external call compiler
#       └── external-call-integration-test/  # This test suite
#
# Usage:
#   ./setup.sh              # Full setup (build both)
#   ./setup.sh --daml-only  # Build only daml compiler
#   ./setup.sh --check      # Check if everything is built
#   ./setup.sh --help       # Show this help

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(dirname "$SCRIPT_DIR")"
DAML_REPO="$(dirname "$TEST_DIR")"
SDK_DIR="$DAML_REPO/sdk"
CANTON_REPO="$(dirname "$DAML_REPO")/canton"

# Binaries
DAMLC="$SDK_DIR/bazel-bin/compiler/damlc/damlc"
CANTON_SDK="$SDK_DIR/bazel-bin/canton/community_app"

# ============================================================
# Helper Functions
# ============================================================

check_prerequisites() {
    echo "Checking prerequisites..."

    local missing=()

    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi

    if [ ! -d "$SDK_DIR/dev-env" ]; then
        missing+=("dev-env (not found at $SDK_DIR/dev-env)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}ERROR: Missing prerequisites:${NC}"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done
        exit 1
    fi

    echo -e "${GREEN}Prerequisites OK${NC}"
}

check_status() {
    echo "============================================================"
    echo "External Call Integration Test Status"
    echo "============================================================"
    echo ""
    echo "Directories:"
    echo "  Daml SDK:    $SDK_DIR"
    echo "  Canton repo: $CANTON_REPO"
    echo "  Test dir:    $TEST_DIR"
    echo ""

    # Check damlc
    if [ -x "$DAMLC" ]; then
        echo -e "Daml compiler:  ${GREEN}Built${NC} at $DAMLC"
    else
        echo -e "Daml compiler:  ${YELLOW}Not built${NC}"
    fi

    # Check canton
    if [ -x "$CANTON_SDK" ]; then
        echo -e "Canton (SDK):   ${GREEN}Built${NC} at $CANTON_SDK"
    else
        echo -e "Canton (SDK):   ${YELLOW}Not built${NC}"
    fi

    # Check DAR
    DAR="$TEST_DIR/.daml/dist/external-call-integration-test-1.0.0.dar"
    if [ -f "$DAR" ]; then
        echo -e "Test DAR:       ${GREEN}Built${NC}"
    else
        echo -e "Test DAR:       ${YELLOW}Not built${NC}"
    fi

    echo ""
}

build_damlc() {
    echo "============================================================"
    echo "Building Daml Compiler with External Call Support"
    echo "============================================================"
    echo ""

    if [ ! -d "$SDK_DIR" ]; then
        echo -e "${RED}ERROR: SDK directory not found at $SDK_DIR${NC}"
        exit 1
    fi

    cd "$SDK_DIR"

    echo "Initializing dev-env..."
    eval "$(dev-env/bin/dade assist)"

    echo ""
    echo "Building damlc..."
    bazel build //compiler/damlc:damlc

    if [ -x "$DAMLC" ]; then
        echo ""
        echo -e "${GREEN}Daml compiler built successfully${NC}"
    else
        echo -e "${RED}ERROR: Build failed${NC}"
        exit 1
    fi
}

build_canton() {
    echo "============================================================"
    echo "Building Canton"
    echo "============================================================"
    echo ""

    if [ ! -d "$SDK_DIR" ]; then
        echo -e "${RED}ERROR: SDK directory not found at $SDK_DIR${NC}"
        exit 1
    fi

    cd "$SDK_DIR"

    echo "Initializing dev-env..."
    eval "$(dev-env/bin/dade assist)"

    echo ""
    echo "Building Canton..."
    bazel build //canton:community_app

    if [ -x "$CANTON_SDK" ]; then
        echo ""
        echo -e "${GREEN}Canton built successfully${NC}"
    else
        echo -e "${RED}ERROR: Build failed${NC}"
        exit 1
    fi
}

build_dar() {
    echo "============================================================"
    echo "Building Test DAR"
    echo "============================================================"
    echo ""

    if [ ! -x "$DAMLC" ]; then
        echo -e "${RED}ERROR: damlc not found. Run setup.sh first.${NC}"
        exit 1
    fi

    mkdir -p "$TEST_DIR/.daml/dist"

    cd "$SDK_DIR"
    eval "$(dev-env/bin/dade assist)"

    echo "Building test DAR..."
    bazel run //compiler/damlc:damlc -- build \
        --project-root="$TEST_DIR" \
        -o "$TEST_DIR/.daml/dist/external-call-integration-test-1.0.0.dar"

    if [ -f "$TEST_DIR/.daml/dist/external-call-integration-test-1.0.0.dar" ]; then
        echo ""
        echo -e "${GREEN}Test DAR built successfully${NC}"
    else
        echo -e "${RED}ERROR: DAR build failed${NC}"
        exit 1
    fi
}

# ============================================================
# Parse Arguments
# ============================================================

ACTION="full"

while [[ $# -gt 0 ]]; do
    case $1 in
        --check|-c)
            ACTION="check"
            shift
            ;;
        --daml-only)
            ACTION="daml"
            shift
            ;;
        --canton-only)
            ACTION="canton"
            shift
            ;;
        --dar-only)
            ACTION="dar"
            shift
            ;;
        --help|-h)
            echo "External Call Integration Test Setup"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (none)        Full setup (build damlc, canton, and test DAR)"
            echo "  --check       Check what's built"
            echo "  --daml-only   Build only daml compiler"
            echo "  --canton-only Build only canton"
            echo "  --dar-only    Build only test DAR"
            echo "  --help        Show this help"
            echo ""
            echo "Directory structure:"
            echo "  This script expects the following structure:"
            echo ""
            echo "  \$HOME/Code/canton/"
            echo "  ├── canton/     # Canton repo (external call runtime)"
            echo "  └── daml/       # Daml repo (external call compiler)"
            echo "      └── external-call-integration-test/"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

# ============================================================
# Main
# ============================================================

case $ACTION in
    check)
        check_status
        ;;
    daml)
        check_prerequisites
        build_damlc
        build_dar
        ;;
    canton)
        check_prerequisites
        build_canton
        ;;
    dar)
        build_dar
        ;;
    full)
        check_prerequisites
        echo ""
        build_damlc
        echo ""
        build_canton
        echo ""
        build_dar
        echo ""
        echo "============================================================"
        echo -e "${GREEN}Setup Complete!${NC}"
        echo "============================================================"
        echo ""
        echo "Next steps:"
        echo "  ./run_test.sh          # Run happy path tests"
        echo "  ./run_test.sh --all    # Run all tests"
        echo "  ./run_test.sh --help   # See all options"
        ;;
esac
