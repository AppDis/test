#!/usr/bin/env bash
# Levanta el modelo premium (ups-pro) bajo demanda.
# Uso: ./start-premium-model.sh

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/../docker-compose.yml}"

echo "Iniciando modelo premium ups-pro..."
docker compose -f "$COMPOSE_FILE" --profile premium up -d ups-pro

echo "Esperando que ups-pro esté disponible..."
# Un modelo 72B-AWQ tarda típicamente 5-10 min en cargar pesos desde disco
TIMEOUT=600
ELAPSED=0
until curl -sf http://localhost:8004/v1/models > /dev/null 2>&1; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "Timeout: ups-pro no respondió en ${TIMEOUT}s"
    docker compose -f "$COMPOSE_FILE" logs --tail=20 ups-pro
    exit 1
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  echo "  Esperando... (${ELAPSED}s / ${TIMEOUT}s)"
done

echo "ups-pro está listo en http://localhost:8004"
echo ""
echo "Para registrarlo en LiteLLM sin reiniciar:"
echo "  curl -X POST http://localhost:4000/model/new \\"
echo "    -H \"Authorization: Bearer \${LITELLM_MASTER_KEY}\" \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model_name\":\"ups-pro\",\"litellm_params\":{\"model\":\"openai/ups-pro\",\"api_base\":\"http://ups-pro:8000/v1\",\"api_key\":\"none\"}}'"
