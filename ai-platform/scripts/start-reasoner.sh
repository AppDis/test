#!/usr/bin/env bash
# Activa ups-reasoner (DeepSeek-R1-Distill-Qwen-32B) bajo demanda.
#
# El modelo ocupa ~77 GB de la memoria unificada del GB10 (121 GB total).
# No puede correr simultáneamente con ups-main — este script detiene ups-main
# primero, luego levanta ups-reasoner.
#
# Para volver al modo normal: scripts/stop-reasoner.sh

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/../docker-compose.yml}"
LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
MASTER_KEY="${LITELLM_MASTER_KEY:-}"

echo "Deteniendo ups-main para liberar memoria GPU..."
docker compose -f "$COMPOSE_FILE" stop ups-main

echo "Levantando ups-reasoner (DeepSeek-R1-Distill-Qwen-32B)..."
docker compose -f "$COMPOSE_FILE" --profile reasoning up -d ups-reasoner

echo "Esperando que ups-reasoner cargue el modelo en GPU (5-15 min)..."
TIMEOUT=900
ELAPSED=0
until curl -sf http://localhost:8003/v1/models > /dev/null 2>&1; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "Timeout: ups-reasoner no respondió en ${TIMEOUT}s"
    docker compose -f "$COMPOSE_FILE" logs --tail=30 ups-reasoner
    exit 1
  fi
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  echo "  Esperando... (${ELAPSED}s / ${TIMEOUT}s)"
done

echo "ups-reasoner listo."

if [[ -n "$MASTER_KEY" ]]; then
  echo "Registrando ups-reasoner en LiteLLM..."
  curl -sf -X POST "${LITELLM_URL}/model/new" \
    -H "Authorization: Bearer ${MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "model_name": "ups-reasoner",
      "litellm_params": {
        "model": "openai/ups-reasoner",
        "api_base": "http://ups-reasoner:8000/v1",
        "api_key": "none",
        "timeout": 600
      },
      "model_info": {
        "description": "DeepSeek-R1-Distill-Qwen-32B — razonamiento profundo",
        "max_tokens": 8192,
        "input_cost_per_token": 0.00000029,
        "output_cost_per_token": 0.00000029
      }
    }' > /dev/null && echo "ups-reasoner registrado en LiteLLM"
fi

echo ""
echo "ups-reasoner activo. ups-main detenido."
echo "Para volver al modo normal: ./scripts/stop-reasoner.sh"
