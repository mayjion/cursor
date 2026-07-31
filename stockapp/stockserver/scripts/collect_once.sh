#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source .venv/bin/activate 2>/dev/null || true
python - <<'PY'
import asyncio
from app.db.store import init_db
from app.services.dashboard import collect_and_score, primary_codes

init_db()
print("codes", primary_codes())
result = asyncio.run(collect_and_score(force_quote=True))
print("result", result)
PY
