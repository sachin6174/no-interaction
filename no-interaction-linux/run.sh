#!/usr/bin/env bash
# Sets up a venv (with access to system site-packages, needed for pyatspi/gi)
# and launches NoInteraction.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

if [ ! -d ".venv" ]; then
  echo "Creating virtualenv (--system-site-packages, so pyatspi/gi are visible)..."
  python3 -m venv --system-site-packages .venv
fi

source .venv/bin/activate
pip install -q -r requirements.txt

python3 -m no_interaction
