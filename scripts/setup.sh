#!/usr/bin/env bash
# Setup base para equipos NVIDIA GB10 / Ubuntu 24.04
# Automatiza Pasos 2, 3 y 4 (Docker, NVIDIA Container Toolkit, almacenamiento)
# El Paso 1 (drivers) debe validarse manualmente con nvidia-smi antes de ejecutar este script.
#
# Uso:
#   chmod +x scripts/setup.sh
#   sudo ./scripts/setup.sh

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; }
info() { echo -e "  ${YELLOW}[INFO]${NC}  $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC}  $1"; exit 1; }

echo ""
echo -e "${BOLD}==============================${NC}"
echo -e "${BOLD} DGX Base Setup${NC}"
echo -e "${BOLD}==============================${NC}"
echo ""

# Prerequisito: driver NVIDIA funcionando
if ! nvidia-smi > /dev/null 2>&1; then
  fail "nvidia-smi no responde. Instalar driver NVIDIA antes de continuar (ver Paso 1 en docs/base-setup.md)"
fi
ok "Driver NVIDIA detectado: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"

# ─── Paso 2: Docker ───────────────────────────────────────────────────────────
echo ""
echo "[ Paso 2 — Docker ]"

if docker --version > /dev/null 2>&1; then
  ok "Docker ya instalado: $(docker --version)"
else
  info "Instalando Docker..."
  apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
  apt update
  apt install -y ca-certificates curl gnupg apt-transport-https lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  ok "Docker instalado"
fi

# Agregar usuario al grupo docker
REAL_USER="${SUDO_USER:-$USER}"
if ! groups "$REAL_USER" | grep -q docker; then
  usermod -aG docker "$REAL_USER"
  ok "Usuario $REAL_USER agregado al grupo docker"
else
  ok "Usuario $REAL_USER ya está en el grupo docker"
fi

# ─── Paso 3: NVIDIA Container Toolkit ────────────────────────────────────────
echo ""
echo "[ Paso 3 — NVIDIA Container Toolkit ]"

if ! nvidia-ctk --version > /dev/null 2>&1; then
  info "Instalando NVIDIA Container Toolkit..."
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

  apt update
  apt install -y nvidia-container-toolkit
  ok "NVIDIA Container Toolkit instalado"
else
  ok "NVIDIA Container Toolkit ya instalado: $(nvidia-ctk --version | head -1)"
fi

info "Configurando runtime nvidia en Docker..."
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
ok "Runtime nvidia registrado en Docker"

# ─── Paso 4: Almacenamiento ───────────────────────────────────────────────────
echo ""
echo "[ Paso 4 — Almacenamiento ]"

if mountpoint -q /data; then
  ok "/data ya montado: $(df -h /data | tail -1 | awk '{print $2" total, "$4" disponible"}')"
else
  info "Preparando partición /data en /dev/nvme0n1..."

  if ! lsblk /dev/nvme0n1p3 > /dev/null 2>&1; then
    parted -a optimal /dev/nvme0n1 mkpart primary ext4 512GB 100% --script
    ok "Partición nvme0n1p3 creada"
    mkfs.ext4 /dev/nvme0n1p3
    ok "Partición formateada (ext4)"
  else
    ok "Partición nvme0n1p3 ya existe"
  fi

  mkdir -p /data
  mount /dev/nvme0n1p3 /data

  if ! grep -q '/dev/nvme0n1p3' /etc/fstab; then
    echo "/dev/nvme0n1p3 /data ext4 defaults 0 2" >> /etc/fstab
    ok "Entrada agregada a /etc/fstab"
  fi

  ok "/data montado: $(df -h /data | tail -1 | awk '{print $2" total, "$4" disponible"}')"
fi

mkdir -p /data/models
chown -R "$REAL_USER:$REAL_USER" /data
ok "Permisos de /data asignados a $REAL_USER"

# ─── Resumen ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=============================="
echo " Setup completado"
echo -e "==============================${NC}"
echo ""
echo "  GPU:     $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
echo "  Docker:  $(docker --version)"
echo "  Runtime: $(docker info 2>/dev/null | grep -i 'nvidia' | head -1 | xargs)"
echo "  /data:   $(df -h /data | tail -1 | awk '{print $4" disponibles de "$2}')"
echo ""
echo -e "  ${YELLOW}Abre una nueva terminal para que el grupo docker tome efecto.${NC}"
echo ""
