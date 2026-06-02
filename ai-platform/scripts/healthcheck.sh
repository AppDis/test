#!/usr/bin/env bash
# Verifica el estado de todos los servicios de la plataforma.
# Uso: ./healthcheck.sh

set -euo pipefail

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
MASTER_KEY="${LITELLM_MASTER_KEY:-}"

# Colores solo si stdout es terminal
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; NC=''
fi

ok()   { echo "  [OK]    $1"; }
warn() { echo "  [WARN]  $1"; }
fail() { echo "  [FAIL]  $1"; }

# Chequeo HTTP dentro del contenedor (para servicios con expose, no ports)
check_container_http() {
  local container="$1"
  local path="$2"
  local label="$3"
  if docker exec "$container" curl -sf --max-time 5 "http://localhost${path}" > /dev/null 2>&1; then
    ok "$label"
  else
    fail "$label → http://localhost${path} (dentro de $container)"
  fi
}

# Chequeo HTTP desde el host (para servicios con ports publicados)
check_host_http() {
  local url="$1"
  local label="$2"
  if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
    ok "$label"
  else
    fail "$label → $url no responde"
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

EDU_PRO_STATUS=$(docker inspect --format='{{.State.Status}}' "edu-pro" 2>/dev/null || echo "not found")
if [[ "$EDU_PRO_STATUS" == "running" ]]; then
  ok "edu-pro (running) [premium activo]"
else
  warn "edu-pro ($EDU_PRO_STATUS) [premium detenido — normal]"
fi

echo ""
echo "[ Endpoints HTTP ]"

# LiteLLM: expose-only → usar docker exec
check_container_http "litellm"      "/health"         "LiteLLM /health"

# vLLM: puertos enlazados a 127.0.0.1 → chequear desde host
check_host_http "http://localhost:8001/v1/models" "edu-fast  /v1/models"
check_host_http "http://localhost:8002/v1/models" "edu-main  /v1/models"
check_host_http "http://localhost:8003/v1/models" "edu-reasoner /v1/models"

# Servicios de observabilidad: expose-only → usar docker exec
check_container_http "prometheus"   "/-/healthy"      "Prometheus"
check_container_http "grafana"      "/api/health"     "Grafana"
check_container_http "node-exporter" "/metrics"       "Node Exporter"
check_container_http "cadvisor"     "/healthz"        "cAdvisor"
check_container_http "dcgm-exporter" "/metrics"       "DCGM Exporter"

echo ""
echo "[ Modelos disponibles en LiteLLM ]"
if [[ -n "$MASTER_KEY" ]]; then
  MODELS=$(docker exec litellm curl -sf --max-time 10 \
    -H "Authorization: Bearer $MASTER_KEY" \
    http://localhost:4000/v1/models 2>/dev/null | jq -r '.data[].id' 2>/dev/null || echo "")
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
if nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu,utilization.gpu \
     --format=csv,noheader 2>/dev/null; then
  true
else
  fail "nvidia-smi no disponible o GPU sin acceso"
fi

echo ""
echo "=============================="
echo " Health check completado"
echo "=============================="
