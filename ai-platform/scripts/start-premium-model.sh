#!/usr/bin/env bash
# Levanta el modelo premium (ups-pro) bajo demanda.
# Uso:
#   ./start-premium-model.sh           → Gigabyte (vLLM, espera carga GPU)
#   ./start-premium-model.sh --local   → Mac (contenedor Alpine + registro LiteLLM)

set -euo pipefail

LOCAL=false
for arg in "$@"; do [[ "$arg" == "--local" ]] && LOCAL=true; done

COMPOSE_FILE="${COMPOSE_FILE:-$(dirname "$0")/../docker-compose.yml}"
$LOCAL && COMPOSE_FILE="${COMPOSE_FILE_LOCAL:-$(dirname "$0")/../docker-compose.local.yml}"

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
MASTER_KEY="${LITELLM_MASTER_KEY:-}"

echo "Iniciando modelo premium ups-pro..."
docker compose -f "$COMPOSE_FILE" --profile premium up -d ups-pro

if $LOCAL; then
  # En local, ups-pro es un contenedor Alpine (no hay vLLM).
  # Registrar el alias en LiteLLM apuntando a Ollama.
  echo "Modo local: registrando ups-pro en LiteLLM → Ollama..."
  sleep 3

  if [[ -n "$MASTER_KEY" ]]; then
    curl -sf -X POST "${LITELLM_URL}/model/new" \
      -H "Authorization: Bearer ${MASTER_KEY}" \
      -H "Content-Type: application/json" \
      -d '{
        "model_name": "ups-pro",
        "litellm_params": {
          "model": "openai/llama3.2:3b",
          "api_base": "http://ollama:11434/v1",
          "api_key": "none",
          "timeout": 300
        },
        "model_info": {"description": "Local — alias premium → llama3.2:3b vía Ollama"}
      }' > /dev/null && echo "ups-pro registrado en LiteLLM"
  else
    echo "[WARN] LITELLM_MASTER_KEY no definida — registrar ups-pro manualmente en /ui"
  fi

else
  # Gigabyte: esperar a que vLLM cargue el modelo 72B-AWQ en GPU (3-10 min)
  echo "Esperando que ups-pro (vLLM) esté disponible..."
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

  echo "ups-pro listo en http://localhost:8004"

  if [[ -n "$MASTER_KEY" ]]; then
    echo "Registrando ups-pro en LiteLLM..."
    curl -sf -X POST "${LITELLM_URL}/model/new" \
      -H "Authorization: Bearer ${MASTER_KEY}" \
      -H "Content-Type: application/json" \
      -d '{
        "model_name": "ups-pro",
        "litellm_params": {
          "model": "openai/ups-pro",
          "api_base": "http://ups-pro:8000/v1",
          "api_key": "none",
          "timeout": 300
        }
      }' > /dev/null && echo "ups-pro registrado en LiteLLM"
  fi
fi

echo ""
echo "ups-pro activo. Probar con:"
echo "  curl http://localhost/v1/chat/completions \\"
echo "    -H 'Authorization: Bearer \${LITELLM_MASTER_KEY}' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\":\"ups-pro\",\"messages\":[{\"role\":\"user\",\"content\":\"Hola\"}]}'"
