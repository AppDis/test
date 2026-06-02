#!/usr/bin/env bash
# Detiene el modelo premium (ups-pro) para liberar recursos.
# Uso:
#   ./stop-premium-model.sh           → Gigabyte (libera GPU y memoria)
#   ./stop-premium-model.sh --local   → Mac (detiene contenedor Alpine)

set -euo pipefail

LOCAL=false
for arg in "$@"; do [[ "$arg" == "--local" ]] && LOCAL=true; done

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/../docker-compose.yml}"
$LOCAL && COMPOSE_FILE="${COMPOSE_FILE_LOCAL:-$(dirname "$0")/../docker-compose.local.yml}"

echo "Deteniendo modelo premium ups-pro..."
docker compose -f "$COMPOSE_FILE" stop ups-pro

if $LOCAL; then
  echo "ups-pro detenido (contenedor local)."
else
  echo "ups-pro detenido. GPU y memoria liberadas."
fi

echo ""
docker compose -f "$COMPOSE_FILE" ps ups-pro
