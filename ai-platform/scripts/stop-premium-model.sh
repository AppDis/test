#!/usr/bin/env bash
# Detiene el modelo premium (ups-pro) para liberar GPU y memoria.
# Uso: ./stop-premium-model.sh

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/../docker-compose.yml}"

echo "Deteniendo modelo premium ups-pro..."
docker compose -f "$COMPOSE_FILE" stop ups-pro

echo "ups-pro detenido. GPU y memoria liberadas."
echo ""
docker compose -f "$COMPOSE_FILE" ps ups-pro
