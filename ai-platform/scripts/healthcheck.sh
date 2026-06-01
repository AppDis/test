#!/usr/bin/env bash
# Verifica el estado de todos los servicios de la plataforma.
# Uso: ./healthcheck.sh

set -euo pipefail

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
MASTER_KEY="${LITELLM_MASTER_KEY:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC}  $1"; }

check_http() {
  local name="$1"
  local url="$2"
  if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
    ok "$name"
  else
    fail "$name → $url no responde"
  fi
}

echo "=============================="
echo " AI Platform — Health Check"
echo "=============================="
echo ""

echo "[ Contenedores Docker ]"
for svc in nginx litellm postgres redis edu-fast edu-main edu-reasoner \
            prometheus grafana alertmanager dcgm-exporter node-exporter cadvisor; do
  STATUS=$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null || echo "not found")
  if [[ "$STATUS" == "running" ]]; then
    ok "$svc (running)"
  elif [[ "$STATUS" == "not found" ]]; then
    warn "$svc (no encontrado)"
  else
    fail "$svc ($STATUS)"
  fi
done

# edu-pro es opcional
EDU_PRO_STATUS=$(docker inspect --format='{{.State.Status}}' "edu-pro" 2>/dev/null || echo "not found")
if [[ "$EDU_PRO_STATUS" == "running" ]]; then
  ok "edu-pro (running) [premium activo]"
else
  warn "edu-pro ($EDU_PRO_STATUS) [premium detenido — normal]"
fi

echo ""
echo "[ Endpoints HTTP ]"
check_http "LiteLLM /health"     "${LITELLM_URL}/health"
check_http "edu-fast  /health"   "http://localhost:8001/health"
check_http "edu-main  /health"   "http://localhost:8002/health"
check_http "edu-reasoner /health" "http://localhost:8003/health"
check_http "Prometheus"          "http://localhost:9090/-/healthy"
check_http "Grafana"             "http://localhost:3000/api/health"
check_http "Node Exporter"       "http://localhost:9100/metrics"
check_http "cAdvisor"            "http://localhost:8080/healthz"
check_http "DCGM Exporter"       "http://localhost:9400/metrics"

echo ""
echo "[ Modelos disponibles en LiteLLM ]"
if [[ -n "$MASTER_KEY" ]]; then
  MODELS=$(curl -sf --max-time 10 \
    -H "Authorization: Bearer $MASTER_KEY" \
    "${LITELLM_URL}/v1/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null || echo "")
  if [[ -n "$MODELS" ]]; then
    while IFS= read -r model; do
      ok "$model"
    done <<< "$MODELS"
  else
    fail "No se pudo obtener lista de modelos"
  fi
else
  warn "LITELLM_MASTER_KEY no definida — omitiendo validación de modelos"
fi

echo ""
echo "[ GPU ]"
if docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 \
     nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu,utilization.gpu \
     --format=csv,noheader 2>/dev/null; then
  true
else
  fail "nvidia-smi no disponible o GPU sin acceso"
fi

echo ""
echo "=============================="
echo " Health check completado"
echo "=============================="
