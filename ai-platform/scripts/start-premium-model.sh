#!/usr/bin/env bash
# Levanta el modelo premium (edu-pro) bajo demanda.
# Uso: ./start-premium-model.sh

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/../docker-compose.yml}"

echo "Iniciando modelo premium edu-pro..."
docker compose -f "$COMPOSE_FILE" --profile premium up -d edu-pro

echo "Esperando que edu-pro esté disponible..."
TIMEOUT=120
ELAPSED=0
until curl -sf http://localhost:8004/health > /dev/null 2>&1; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "Timeout: edu-pro no respondió en ${TIMEOUT}s"
    exit 1
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  Esperando... (${ELAPSED}s)"
done

echo "edu-pro está listo en http://localhost:8004"
echo ""
echo "Para habilitar acceso desde LiteLLM, verificar que el modelo 'edu-pro'"
echo "esté disponible en: ${LITELLM_URL:-http://localhost:4000}/v1/models"
