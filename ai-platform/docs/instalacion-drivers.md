# Instalación del stack base: NVIDIA Driver + Docker + NVIDIA Container Toolkit

Guía paso a paso para preparar el equipo antes de ejecutar `docker compose up`.  
Sistema operativo objetivo: **Ubuntu 22.04 LTS** (o 24.04).

---

## Fase 0 — Verificaciones previas

```bash
# Versión del sistema operativo
lsb_release -a

# Kernel actual
uname -r

# GPU detectada por el sistema
lspci | grep -i nvidia

# Verificar si ya hay driver instalado
nvidia-smi 2>/dev/null && echo "Driver OK" || echo "Sin driver"
```

Si `nvidia-smi` ya responde → saltar directo a la **Fase 2** (Docker).

---

## Fase 1 — Instalar drivers NVIDIA

### 1.1 Actualizar el sistema

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential dkms linux-headers-$(uname -r)
```

### 1.2 Limpiar drivers anteriores (si hubiera)

```bash
sudo apt purge -y 'nvidia-*' 'libnvidia-*' cuda-drivers 2>/dev/null || true
sudo apt autoremove -y
```

### 1.3 Agregar repositorio oficial NVIDIA CUDA

```bash
# Descargar el keyring y la configuración del repo
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
```

> Para Ubuntu 24.04 reemplazar `ubuntu2204` por `ubuntu2404` en la URL.

### 1.4 Ver drivers disponibles y elegir versión

```bash
apt-cache search nvidia-driver | grep "^nvidia-driver-[0-9]" | sort -V
```

Instalar el driver recomendado (mínimo **550** para CUDA 12.4 que requiere vLLM):

```bash
# Opción A: detección automática del driver recomendado
sudo ubuntu-drivers install

# Opción B: versión específica (recomendado para producción)
sudo apt install -y nvidia-driver-570
```

### 1.5 Reiniciar y verificar

```bash
sudo reboot
```

Después del reinicio:

```bash
nvidia-smi
```

Salida esperada (ejemplo):

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 570.xx     Driver Version: 570.xx    CUDA Version: 12.x                     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|   0  NVIDIA ...                     Off | 00000000:xx:xx.0  Off  |                    0 |
+-----------------------------------------------------------------------------------------+
```

> Si `nvidia-smi` no responde después del reinicio, verificar que Secure Boot esté deshabilitado en la BIOS/UEFI.

### 1.6 Desactivar Secure Boot (si aplica)

```bash
# Verificar estado de Secure Boot
mokutil --sb-state
```

Si dice `SecureBoot enabled`, entrar a la BIOS y desactivarlo,  
o registrar el módulo con MOK:

```bash
sudo mokutil --disable-validation
```

---

## Fase 2 — Instalar Docker Engine

### 2.1 Eliminar versiones antiguas

```bash
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
```

### 2.2 Instalar dependencias

```bash
sudo apt install -y \
  ca-certificates curl gnupg lsb-release apt-transport-https
```

### 2.3 Agregar repositorio oficial Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
```

### 2.4 Instalar Docker CE

```bash
sudo apt install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

### 2.5 Agregar usuario al grupo docker

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### 2.6 Verificar Docker

```bash
docker --version
docker compose version
docker run --rm hello-world
```

Salida esperada: `Hello from Docker!`

---

## Fase 3 — Instalar NVIDIA Container Toolkit

Este componente es el puente entre Docker y el driver NVIDIA del host.

### 3.1 Agregar repositorio NVIDIA Container Toolkit

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
```

### 3.2 Instalar

```bash
sudo apt install -y nvidia-container-toolkit
```

### 3.3 Configurar Docker para usar el runtime NVIDIA

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Esto agrega el runtime `nvidia` al archivo `/etc/docker/daemon.json`:

```json
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
```

### 3.4 Verificar

```bash
nvidia-ctk --version
docker info | grep -i runtime
```

Debe aparecer `nvidia` en la lista de runtimes.

---

## Fase 4 — Validación completa

### 4.1 GPU accesible dentro de un contenedor

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

Debe mostrar el mismo output que `nvidia-smi` en el host.

### 4.2 CUDA funcional

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 \
  nvidia-smi --query-gpu=name,memory.total,driver_version,compute_cap \
  --format=csv,noheader
```

### 4.3 Validar que vLLM puede acceder a la GPU

```bash
docker run --rm --gpus all \
  --ipc=host \
  -e NVIDIA_VISIBLE_DEVICES=all \
  vllm/vllm-openai:latest \
  python3 -c "import torch; print('CUDA:', torch.cuda.is_available()); print('GPUs:', torch.cuda.device_count())"
```

Salida esperada:
```
CUDA: True
GPUs: 1       ← o más según el equipo
```

---

## Fase 5 — Preparar almacenamiento de modelos

```bash
# Crear el directorio donde se guardarán los modelos
sudo mkdir -p /data/models
sudo chown $USER:$USER /data/models

# Verificar espacio disponible
df -h /data
```

Espacio recomendado por modelo:

| Modelo | Tamaño aproximado |
|--------|------------------|
| Qwen2.5-7B-Instruct | ~15 GB |
| Qwen2.5-32B-Instruct-AWQ | ~20 GB |
| DeepSeek-R1-Distill-Qwen-32B | ~65 GB |
| Qwen2.5-72B-Instruct-AWQ | ~40 GB |

---

## Resumen de comandos de verificación

```bash
# Estado completo del sistema
echo "=== OS ===" && lsb_release -a
echo "=== GPU ===" && nvidia-smi
echo "=== CUDA ===" && nvidia-smi | grep "CUDA Version"
echo "=== Docker ===" && docker --version && docker compose version
echo "=== NVIDIA Runtime ===" && docker info | grep -i nvidia
echo "=== Disco modelos ===" && df -h /data/models
echo "=== GPU en contenedor ===" && docker run --rm --gpus all \
  nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L
```

---

## Problemas comunes

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| `nvidia-smi: command not found` | Driver no instalado | Repetir Fase 1 |
| `nvidia-smi` falla tras instalar | Secure Boot activo | Desactivar en BIOS |
| `docker: Error no such runtime: nvidia` | Toolkit no configurado | Repetir paso 3.3 |
| `CUDA error: no kernel image` | Driver viejo para la GPU | Actualizar a driver ≥ 550 |
| `Failed to initialize NVML` | Driver cargado pero sin reinicio | `sudo reboot` |
| `vLLM OOM al cargar modelo` | GPU memory insuficiente | Reducir `--max-model-len` o usar modelo más pequeño |
