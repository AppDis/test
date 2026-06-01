#!/usr/bin/env bash
# Crea una API Key en LiteLLM para un estudiante usando su correo institucional.
# Uso: ./create-user-key.sh <correo@institucion.edu.ec> [modelo1,modelo2,...]

set -euo pipefail

LITELLM_URL="${LITELLM_URL:-http://localhost:4000}"
MASTER_KEY="${LITELLM_MASTER_KEY:?La variable LITELLM_MASTER_KEY no está definida}"

EMAIL="${1:?Uso: $0 <correo@institucion.edu.ec> [modelos]}"
MODELS="${2:-edu-fast,edu-main,edu-reasoner}"

# Validar formato de correo institucional básico
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Error: correo inválido: $EMAIL"
  exit 1
fi

echo "Creando API Key para: $EMAIL"
echo "Modelos permitidos: $MODELS"

# Construir array de modelos en JSON
MODELS_JSON=$(echo "$MODELS" | tr ',' '\n' | jq -Rn '[inputs]')

RESPONSE=$(curl -s -X POST "${LITELLM_URL}/key/generate" \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"${EMAIL}\",
    \"user_email\": \"${EMAIL}\",
    \"models\": ${MODELS_JSON},
    \"metadata\": {
      \"user_email\": \"${EMAIL}\",
      \"created_by\": \"admin\",
      \"purpose\": \"pilot-sistemas-distribuidos\"
    }
  }")

if echo "$RESPONSE" | jq -e '.key' > /dev/null 2>&1; then
  KEY=$(echo "$RESPONSE" | jq -r '.key')
  echo ""
  echo "API Key creada exitosamente:"
  echo "  Usuario : $EMAIL"
  echo "  API Key : $KEY"
  echo "  Modelos : $MODELS"
  echo ""
  echo "Endpoint: ${LITELLM_URL}/v1/chat/completions"
else
  echo "Error al crear la clave:"
  echo "$RESPONSE" | jq .
  exit 1
fi
