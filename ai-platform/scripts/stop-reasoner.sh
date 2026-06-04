#!/usr/bin/env bash
# Detiene ups-reasoner y restaura ups-main al modo normal.

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/../docker-compose.yml}"

echo "Deteniendo ups-reasoner..."
docker compose -f "$COMPOSE_FILE" stop ups-reasoner

echo "Reiniciando ups-main..."
docker compose -f "$COMPOSE_FILE" up -d ups-main

echo ""
echo "Modo normal restaurado: ups-fast + ups-main activos."
