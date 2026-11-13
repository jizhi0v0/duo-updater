#!/bin/bash
# Run the HTTP and automatic-update simulations without using the app's state.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/duo-http-simulation.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

export DUO_STATE_DIR="$SCRATCH/state"

# Listing builds the same bundle that is run below. Check every suite so a
# renamed or missing test cannot turn a zero-test run into a successful audit.
swift test --package-path "$REPO/DuoUpdaterCore" \
    --disable-automatic-resolution --jobs 4 list > "$SCRATCH/tests.txt"
for suite in HTTPDownloadStatusSimulationTests HTTPVersionSourceSimulationTests \
             HTTPRetryAfterSimulationTests HTTPAutomaticUpdateSimulationTests \
             HTTPAutomaticUpdateFailureSimulationTests HTTPAutomaticFallbackSimulationTests; do
    if ! grep -F "$suite/" "$SCRATCH/tests.txt" >/dev/null; then
        printf 'Missing simulation suite: %s\n' "$suite" >&2
        exit 1
    fi
done

swift test --package-path "$REPO/DuoUpdaterCore" \
    --skip-build --filter 'HTTP.*SimulationTests'
