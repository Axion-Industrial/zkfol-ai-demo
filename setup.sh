#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
DEV=0
EDITABLE=0
for arg in "$@"; do
  case "$arg" in
    --dev) DEV=1 ;;
    --editable) EDITABLE=1 ;;
    -h|--help)
      cat <<'HELP'
Usage: ./setup.sh [--dev] [--editable]

Creates .venv. By default this bundle runs directly from source using
PYTHONPATH and the vendored SymPy copy, so no network access is needed.

Options:
  --dev       Try to install pytest into the venv for the regression suite.
  --editable  Also pip-install zkfol_reference and zkfol_zinc_adapter editable.
              This is closer to a normal developer install but may need network
              access for build/dependency tooling on a fresh machine.
HELP
      exit 0 ;;
    *) echo "Unknown setup option: $arg" >&2; exit 2 ;;
  esac
done

cd "$ROOT"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Could not find Python executable: $PYTHON_BIN" >&2
  echo "Set PYTHON_BIN=/path/to/python3 or install Python 3.10+." >&2
  exit 1
fi

if [ ! -d .venv ]; then
  "$PYTHON_BIN" -m venv .venv
fi

export PYTHONPATH="$ROOT/zkfol_reference/src:$ROOT/zkfol_zinc_adapter/src:$ROOT/vendor:${PYTHONPATH:-}"

if [ "$EDITABLE" = 1 ]; then
  # Avoid build isolation so this works on machines whose venv already has
  # setuptools. If it fails, the source-backed wrapper still works.
  .venv/bin/python -m pip install --no-build-isolation --no-deps -e ./zkfol_reference
  .venv/bin/python -m pip install --no-build-isolation --no-deps -e ./zkfol_zinc_adapter
fi

if [ "$DEV" = 1 ]; then
  .venv/bin/python -m pip install pytest || {
    echo "Warning: could not install pytest. The normal demo commands still work." >&2
  }
fi

.venv/bin/python - <<'PY'
import sys
import zkfol
import zkfol_zinc_adapter
import sympy
print('Python:', sys.version.split()[0])
print('zkfol package: ok')
print('zkfol-zinc-adapter:', zkfol_zinc_adapter.__version__)
print('sympy:', sympy.__version__)
PY

echo
echo "Setup complete. Try:"
echo "  ./folzinc doctor"
echo "  ./folzinc demo"
echo "  ./zkfol_zinc_adapter/folzinc demo   # same environment, adapter-local wrapper"
echo "  ./folzinc build          # requires Rust/Cargo >= 1.85"
echo "  ./folzinc demo --zinc    # requires Rust/Cargo >= 1.85"
