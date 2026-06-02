#!/usr/bin/env bash
# Verifica el estado de todos los servicios de la plataforma.
# Uso:
#   ./healthcheck.sh            → entorno Gigabyte (producción)
#   ./healthcheck.sh --local    → entorno Mac local (Ollama)

set -euo pipefail

LOCAL=false
for arg in "$@"; do [[ "$arg" == "--local" ]] && LOCAL=true; done

MASTER_KEY="${LITELLM_MASTER_KEY:-}"

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BOLD=''; NC=''
fi

ok()   { echo "  [OK]    $1"; }
warn() { echo "  [WARN]  $1"; }
fail() { echo "  [FAIL]  $1"; }

check_container() {
  local name="$1"
  local optional="${2:-false}"
  local STATUS
  STATUS=$(docker inspect --format='{{.State.Status}}' "$name" 2>/dev/null || echo "not found")
  if [[ "$STATUS" == "running" ]]; then
    ok "$name (running)"
  elif [[ "$STATUS" == "not found" ]] && [[ "$optional" == "true" ]]; then
    warn "$name (no encontrado — opcional)"
  elif [[ "$STATUS" == "not found" ]]; then
    warn "$name (no encontrado)"
  else
    fail "$name ($STATUS)"
  fi
}

check_container_http() {
  local container="$1" path="$2" label="$3"
  if docker exec "$container" curl -sf --max-time 5 "http://localhost${path}" > /dev/null 2>&1; then
    ok "$label"
  else
    fail "$label (dentro de $container, path: $path)"
  fi
}

check_host_http() {
  local url="$1" label="$2"
  if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
    ok "$label"
  else
    fail "$label → $url"
  fi
}

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}==============================${NC}"
if $LOCAL; then
  echo -e "${BOLD} UPS AI Platform — Local (Mac)${NC}"
else
  echo -e "${BOLD} UPS AI Platform — Gigabyte${NC}"
fi
echo -e "${BOLD}==============================${NC}"
echo ""

# ─── Contenedores comunes ─────────────────────────────────────────────────────
echo "[ Contenedores ]"
check_container "ups-nginx"
check_container "ups-litellm"
check_container "ups-postgres"
check_container "ups-redis"

if $LOCAL; then
  check_container "ups-ollama"
else
  check_container "ups-fast"
  check_container "ups-main"
  check_container "ups-reasoner"
fi

UPS_PRO_STATUS=$(docker inspect --format='{{.State.Status}}' "ups-pro" 2>/dev/null || echo "not found")
if [[ "$UPS_PRO_STATUS" == "running" ]]; then
  ok "ups-pro (running) [premium activo]"
else
  warn "ups-pro ($UPS_PRO_STATUS) [premium detenido — normal]"
fi

# ─── Endpoints HTTP ───────────────────────────────────────────────────────────
echo ""
echo "[ Endpoints HTTP ]"

check_host_http  "http://localhost/health"   "nginx → /health"
check_container_http "ups-litellm" "/health" "LiteLLM /health"

if $LOCAL; then
  # Ollama no tiene curl; verificar vía ollama list directamente
  if docker exec ups-ollama ollama list 2>/dev/null | grep -q 'llama3.2'; then
    ok "Ollama — llama3.2:3b disponible"
  else
    fail "Ollama — modelo no cargado"
  fi
else
  check_host_http "http://localhost:8001/v1/models" "ups-fast  /v1/models"
  check_host_http "http://localhost:8002/v1/models" "ups-main  /v1/models"
  check_host_http "http://localhost:8003/v1/models" "ups-reasoner /v1/models"
fi

# ─── Modelos registrados en LiteLLM ──────────────────────────────────────────
echo ""
echo "[ Modelos en LiteLLM ]"
if [[ -n "$MASTER_KEY" ]]; then
  MODELS=$(docker exec ups-litellm curl -sf --max-time 10 \
    -H "Authorization: Bearer $MASTER_KEY" \
    http://localhost:4000/v1/models 2>/dev/null \
    | jq -r '.data[].id' 2>/dev/null || echo "")
  if [[ -n "$MODELS" ]]; then
    while IFS= read -r m; do ok "$m"; done <<< "$MODELS"
  else
    fail "No se pudo obtener lista de modelos"
  fi
else
  warn "LITELLM_MASTER_KEY no definida — omitir validación de modelos"
fi

# ─── GPU / Inferencia ─────────────────────────────────────────────────────────
echo ""
if $LOCAL; then
  echo "[ Ollama — backend local ]"
  OLLAMA_MODELS=$(docker exec ups-ollama ollama list 2>/dev/null || echo "")
  if [[ -n "$OLLAMA_MODELS" ]]; then
    ok "Modelos descargados:"
    echo "$OLLAMA_MODELS" | tail -n +2 | awk '{print "    " $1}'
  else
    fail "Ollama no responde o sin modelos"
  fi
else
  echo "[ GPU Gigabyte ]"
  if nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu \
       --format=csv,noheader 2>/dev/null; then
    true
  else
    fail "nvidia-smi no disponible"
  fi
fi

echo ""
echo -e "${BOLD}=============================="
echo " Health check completado"
echo -e "==============================${NC}"
echo ""
