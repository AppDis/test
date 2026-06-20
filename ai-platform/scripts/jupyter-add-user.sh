#!/usr/bin/env bash
# Crea un usuario en JupyterHub y su directorio home.
# Uso: ./jupyter-add-user.sh alumno01 [alumno02 alumno03 ...]
# O con CSV: ./jupyter-add-user.sh --csv alumnos.csv

set -euo pipefail

JUPYTER_URL="${JUPYTER_URL:-http://localhost:80/jupyter}"
ADMIN_USER="${JUPYTER_ADMIN_USER:-admin}"
ADMIN_PASS="${JUPYTER_ADMIN_PASS:-}"

if [[ -z "$ADMIN_PASS" ]]; then
  echo "Error: define JUPYTER_ADMIN_PASS"
  exit 1
fi

add_user() {
  local username="$1"
  echo -n "  Creando usuario '$username'... "
  curl -sf -X POST "${JUPYTER_URL}/hub/api/users/${username}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H "Content-Type: application/json" > /dev/null && echo "OK" || echo "ya existe"

  # Crear directorio home en el volumen
  docker exec ups-jupyter bash -c "
    id '${username}' &>/dev/null || useradd -m -s /bin/bash '${username}'
    mkdir -p '/home/${username}/notebooks'
    chown -R '${username}:${username}' '/home/${username}'
  "
}

if [[ "${1:-}" == "--csv" ]]; then
  CSV="${2:-}"
  [[ -f "$CSV" ]] || { echo "Archivo no encontrado: $CSV"; exit 1; }
  while IFS=',' read -r username _rest; do
    [[ -z "$username" || "$username" == \#* ]] && continue
    add_user "$username"
  done < "$CSV"
else
  for username in "$@"; do
    add_user "$username"
  done
fi

echo ""
echo "Usuarios creados. Enviar link de primer acceso:"
echo "  https://<tudominio>/jupyter/hub/login"
