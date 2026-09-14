#!/usr/bin/env bash
# Refresh only this repository's existing references, with pinned same-project
# GitHub migration. Bootstrap missing clones separately after approval.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec python3 "$ROOT/scripts/update-references.py" "$@"
