# External Call Integration Test

Integration tests for the external call feature in Daml/Canton. This feature allows Daml code to make deterministic HTTP calls to external services during transaction execution.

## Overview

The external call feature enables:
- **Daml contracts** to call external services using `DA.External.externalCall`
- **Deterministic execution**: Results are stored in the transaction and replayed on validation
- **Observer replay**: Observers can process transactions without external service access

### Key Architecture

```
participant1 (signatory)              participant2 (observer)
  - has extension configured            - NO extension configured
  - makes HTTP calls to service         - uses stored results from transaction
  - stores results in transaction       - validates using stored results
```

## Prerequisites

1. **Nix dev-env** - For building the Daml SDK
2. **Python 3** - For the mock external service
3. **The daml repo** - With external call compiler changes (this repo)
4. **Canton with external call runtime** - See "Canton Runtime" section below

### Canton Runtime Requirement

The integration tests require a Canton runtime with external call support. The external
call feature is implemented across two repositories:

- **daml repo** (this repo) - Compiler support (`DA.External` module, `BEExternalCall` builtin)
- **canton repo** - Runtime support (interpreter, transaction encoding, HTTP client)

The Canton binary in the daml SDK uses upstream Canton maven artifacts. Until the canton
changes are merged upstream, you need to build Canton from the canton repo.

### Directory Structure

The expected directory structure is:
```
$HOME/Code/canton/
├── canton/     # Canton repo (if using local canton with external call runtime)
└── daml/       # This repo (daml with external call compiler support)
    ├── sdk/    # Daml SDK source
    └── external-call-integration-test/  # This test suite
```

## Quick Start

### 1. Build Daml Compiler and Test DAR

```bash
./scripts/setup.sh
```

### 2. Build Canton from Canton Repo

```bash
cd ../../../canton               # Go to canton repo
export PATH="$HOME/.dpm/bin:$PATH"
sbt --batch 'project community-app' 'assembly'
cd -
```

### 3. Run Tests

```bash
CANTON_CMD="$(pwd)/scripts/canton-local.sh" ./run_test.sh --all
```

### Running Tests

```bash
./run_test.sh --all    # Run all 37 tests
./run_test.sh          # Just happy path tests (default)
./run_test.sh --help   # See all options
```

## Test Suites

| Flag | Description | Tests |
|------|-------------|-------|
| `--happy` | Basic external call + observer replay | 5 |
| `--errors` | HTTP error codes (400-504) | 8 |
| `--retry` | Retry logic (503, rate-limit) | 3 |
| `--auth` | JWT authentication | 3 |
| `--tls` | TLS/HTTPS connectivity | 2 |
| `--timeout` | Request timeouts | 2 |
| `--edge` | Input/output edge cases | 9 |
| `--multi` | Multi-participant scenarios | 4 |
| `--config` | Config edge cases | 3 |
| `--echo` | Echo mode (no HTTP calls) | 2 |

## How It Works

### External Call API

The Daml API for external calls:

```daml
import DA.External

-- Make an external call
result <- externalCall extensionId functionId configHex inputHex
-- Parameters:
--   extensionId: "test-oracle"     -- Extension name from canton config
--   functionId:  "echo"            -- Function within the extension
--   configHex:   "00000000"        -- Config hash (hex, validates service version)
--   inputHex:    "48656c6c6f"      -- Input data (hex encoded)
-- Returns: Response as hex string
```

### Transaction Flow

1. **Submission** (participant1):
   - Contract choice invokes `externalCall`
   - Canton makes HTTP call to extension service
   - Response stored in transaction as `Node.ExternalCall`

2. **Validation** (participant1 + participant2):
   - participant1: May call service again or use cache
   - participant2 (observer): Uses stored result from transaction
   - Both must agree on the result

### Mock Service

The mock service (`scripts/mock_service.py`) simulates various external service behaviors:

| Function ID | Behavior |
|-------------|----------|
| `echo` | Returns input unchanged |
| `error-400` | HTTP 400 Bad Request |
| `error-401` | HTTP 401 Unauthorized |
| `error-500` | HTTP 500 Internal Server Error |
| `error-503` | HTTP 503 Service Unavailable (triggers retry) |
| `retry-once` | 503 first time, 200 second time |
| `rate-limit` | HTTP 429 with Retry-After header |
| `delay-{ms}` | Delays response by specified milliseconds |
| `large-output` | Returns 100KB response |

## Configuration Files

| File | Description |
|------|-------------|
| `canton.conf` | Default: participant1 has extension, participant2 doesn't |
| `canton-auth.conf` | JWT authentication enabled |
| `canton-tls.conf` | TLS/HTTPS enabled |
| `canton-echo.conf` | Echo mode (no HTTP calls) |
| `canton-both-extensions.conf` | Both participants have extension |
| `canton-no-extensions.conf` | Neither participant has extension |

## Manual Testing

### Terminal 1: Start Mock Service

```bash
python3 scripts/mock_service.py 8080
```

### Terminal 2: Run Canton

```bash
cd ..  # Go to daml repo root
export JAVA_OPTS="-Ddar.path=external-call-integration-test/.daml/dist/external-call-integration-test-1.0.0.dar"
sdk/bazel-bin/canton/community_app run \
    -c external-call-integration-test/canton.conf \
    external-call-integration-test/scripts/full_test.canton
```

## Building Components Individually

### Build Daml Compiler Only

```bash
cd sdk
eval "$(dev-env/bin/dade assist)"
bazel build //compiler/damlc:damlc
```

### Build Canton Only

```bash
cd sdk
eval "$(dev-env/bin/dade assist)"
bazel build //canton:community_app
```

### Build Test DAR Only

```bash
cd sdk
eval "$(dev-env/bin/dade assist)"
bazel run //compiler/damlc:damlc -- build \
    --project-root=../external-call-integration-test \
    -o ../external-call-integration-test/.daml/dist/external-call-integration-test-1.0.0.dar
```

## Troubleshooting

### "Extension not configured" error

The participant doesn't have the extension service configured. Check:
1. The canton config file has the extension defined
2. The `extensionId` in Daml matches the config name

### "Invalid hex encoding" error

The `configHex` or `inputHex` parameters must be:
- Even length (each byte is 2 hex chars)
- Only contain characters 0-9, a-f, A-F

### Mock service won't start

Check if port 8080 is in use:
```bash
fuser -k 8080/tcp  # Kill any process using the port
```

### DAR build fails

Make sure you're using the damlc with external call support:
```bash
./scripts/setup.sh --check  # Check if damlc is built
./scripts/setup.sh --daml-only  # Rebuild if needed
```

## Current Status

**✅ Tests are working.** Build Canton from the canton repo and run tests with `CANTON_CMD`.

The external call feature spans both the daml and canton repos. Once the canton changes
are merged upstream, the SDK's Canton will work and you won't need to build from source.

## Scripts Reference

| Script | Description |
|--------|-------------|
| `scripts/setup.sh` | Build damlc and test DAR |
| `scripts/canton-local.sh` | Run Canton from local canton repo build |
| `scripts/mock_service.py` | Mock external service for testing |

## Related Documentation

- [TEST_PLAN.md](TEST_PLAN.md) - Detailed test coverage matrix
- [DA.External module](../sdk/compiler/damlc/daml-stdlib-src/DA/External.daml) - Daml API documentation
