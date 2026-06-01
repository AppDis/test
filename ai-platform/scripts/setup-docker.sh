#!/usr/bin/env bash
# Instala Docker Engine y NVIDIA Container Toolkit en Ubuntu 22.04 / 24.04.
# Uso: sudo ./setup-docker.sh
#
# Requisito previo: driver NVIDIA instalado (nvidia-smi debe responder).

set -euo pipefail

# ─── Colores ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
  BOLD=''; GREEN=''; YELLOW=''; RED=''; NC=''
fi

step() { echo -e "\n${BOLD}▶ $1${NC}"; }
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
die()  { echo -e "  ${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Verificaciones previas ────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Ejecutar con sudo: sudo $0"

step "Verificando requisitos previos"

# Detectar distribución
if ! command -v lsb_release &>/dev/null; then
  die "lsb_release no encontrado. ¿Es Ubuntu?"
fi

DISTRO=$(lsb_release -si)
CODENAME=$(lsb_release -cs)
[[ "$DISTRO" == "Ubuntu" ]] || die "Este script es para Ubuntu. Detectado: $DISTRO"

ok "Sistema: Ubuntu $CODENAME"

# Verificar driver NVIDIA
if ! command -v nvidia-smi &>/dev/null; then
  die "nvidia-smi no encontrado. Instalar el driver NVIDIA antes de ejecutar este script."
fi
DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
ok "Driver NVIDIA: $DRIVER_VER"

# ─── Paso 1: Limpiar instalaciones anteriores ──────────────────────────────────
step "Limpiando versiones anteriores de Docker"
apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
apt autoremove -y
ok "Limpieza completada"

# ─── Paso 2: Dependencias ──────────────────────────────────────────────────────
step "Instalando dependencias"
apt update -qq
apt install -y ca-certificates curl gnupg apt-transport-https lsb-release
ok "Dependencias instaladas"

# ─── Paso 3: Repositorio Docker ───────────────────────────────────────────────
step "Configurando repositorio oficial de Docker"
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -qq
ok "Repositorio Docker agregado"

# ─── Paso 4: Instalar Docker Engine ───────────────────────────────────────────
step "Instalando Docker Engine"
apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
ok "Docker Engine instalado"

# ─── Paso 5: Habilitar servicio ────────────────────────────────────────────────
step "Habilitando servicio Docker"
systemctl enable docker
systemctl start docker
ok "Servicio docker activo"

# ─── Paso 6: Grupo docker ─────────────────────────────────────────────────────
step "Configurando permisos de usuario"
REAL_USER="${SUDO_USER:-$USER}"
if [[ "$REAL_USER" != "root" ]]; then
  usermod -aG docker "$REAL_USER"
  ok "Usuario '$REAL_USER' agregado al grupo docker"
  warn "Cerrar y volver a abrir sesión (o ejecutar: newgrp docker)"
else
  warn "Ejecutando como root — omitiendo configuración de grupo"
fi

# ─── Paso 7: Verificar Docker ─────────────────────────────────────────────────
step "Verificando Docker"
DOCKER_VER=$(docker --version)
COMPOSE_VER=$(docker compose version)
ok "$DOCKER_VER"
ok "$COMPOSE_VER"

# ─── Paso 8: NVIDIA Container Toolkit ────────────────────────────────────────
step "Instalando NVIDIA Container Toolkit"

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

apt update -qq
apt install -y nvidia-container-toolkit
ok "nvidia-container-toolkit instalado"

# Configurar runtime en Docker
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
ok "Runtime NVIDIA configurado en Docker"

# ─── Paso 9: Validación final ─────────────────────────────────────────────────
step "Validando GPU dentro de contenedor"
if docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L; then
  ok "GPU accesible desde contenedor Docker"
else
  die "GPU no accesible desde contenedor. Revisar logs: journalctl -u docker"
fi

# ─── Resumen ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Instalación completada exitosamente${NC}"
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""
echo "  docker --version       : $(docker --version)"
echo "  docker compose version : $(docker compose version)"
echo "  nvidia-ctk --version   : $(nvidia-ctk --version | head -1)"
echo ""
echo "  Siguiente paso: levantar la plataforma"
echo "    cd ai-platform"
echo "    cp .env.example .env"
echo "    nano .env"
echo "    docker compose up -d"
echo ""
