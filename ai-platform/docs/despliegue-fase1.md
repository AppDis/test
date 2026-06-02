# Despliegue Fase 1 — UPS AI Platform (Gigabyte)

Guía completa para poner en producción la plataforma desde cero.  
Sistema objetivo: **Ubuntu 22.04 / 24.04 LTS** con GPU NVIDIA.

---

## Paso 1 — Validar drivers NVIDIA

```bash
# GPU detectada por el sistema
lspci | grep -i nvidia

# Driver instalado
nvidia-smi
```

**Salida esperada de `nvidia-smi`:**

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 570.xx     Driver Version: 570.xx    CUDA Version: 12.x                     |
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|   0  NVIDIA ...                     Off | 00000000:xx:xx.0  Off  |                    0 |
+-----------------------------------------------------------------------------------------+
```

Si `nvidia-smi` responde → **saltar al Paso 2**.  
Si falla → instalar el driver:

```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential dkms linux-headers-$(uname -r)

# Limpiar drivers anteriores
sudo apt purge -y 'nvidia-*' 'libnvidia-*' cuda-drivers 2>/dev/null || true
sudo apt autoremove -y

# Agregar repositorio oficial NVIDIA (Ubuntu 24.04)
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update

# Instalar driver (mínimo 550 para CUDA 12.4 que requiere vLLM)
sudo apt install -y nvidia-driver-570

# Reiniciar y verificar
sudo reboot
```

> Si usas Ubuntu 22.04 reemplazar `ubuntu2404` por `ubuntu2204` en la URL del keyring.  
> Si `nvidia-smi` falla tras el reinicio, verificar que **Secure Boot esté deshabilitado** en la BIOS.

---

## Paso 2 — Instalar Docker Engine

```bash
# Limpiar versiones anteriores
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo apt autoremove -y

# Dependencias
sudo apt update
sudo apt install -y ca-certificates curl gnupg apt-transport-https lsb-release

# Repositorio oficial Docker
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

# Instalar
sudo apt install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Habilitar servicio
sudo systemctl enable docker
sudo systemctl start docker

# Agregar usuario al grupo docker (evita usar sudo en cada comando)
sudo usermod -aG docker $USER
newgrp docker
```

**Verificar:**

```bash
docker --version
docker compose version
docker run --rm hello-world
```

Salida esperada al final: `Hello from Docker!`

---

## Paso 3 — Habilitar GPU para Docker (NVIDIA Container Toolkit)

Este componente es el puente entre Docker y el driver NVIDIA del host. Sin él, los contenedores vLLM no pueden acceder a la GPU.

```bash
# Agregar repositorio NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configurar runtime NVIDIA en Docker
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

**Verificar que Docker ve la GPU:**

```bash
# Runtime nvidia disponible
docker info | grep -i runtime

# GPU accesible dentro de un contenedor
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

La segunda salida debe ser idéntica a `nvidia-smi` en el host.

**Verificar que CUDA funciona para vLLM:**

```bash
docker run --rm --gpus all --ipc=host \
  -e NVIDIA_VISIBLE_DEVICES=all \
  vllm/vllm-openai:latest \
  python3 -c "import torch; print('CUDA:', torch.cuda.is_available()); print('GPUs:', torch.cuda.device_count())"
```

Salida esperada:
```
CUDA: True
GPUs: 1
```

---

## Paso 4 — Desplegar Fase 1

### 4.1 Clonar el repositorio

```bash
git clone <URL-DEL-REPOSITORIO> ups-ai
cd ups-ai/ai-platform
```

### 4.2 Preparar almacenamiento de modelos

```bash
sudo mkdir -p /data/models
sudo chown $USER:$USER /data/models
df -h /data   # verificar espacio disponible
```

Espacio requerido por modelo:

| Modelo | Tamaño |
|--------|--------|
| Qwen2.5-7B-Instruct | ~15 GB |
| Qwen2.5-32B-Instruct-AWQ | ~20 GB |
| DeepSeek-R1-Distill-Qwen-32B | ~65 GB |
| Qwen2.5-72B-Instruct-AWQ (ups-pro) | ~40 GB |

Total mínimo para los 3 modelos base: **~100 GB libres**.

### 4.3 Descargar modelos

```bash
# Instalar huggingface-cli si no está
pip install huggingface-hub

# Qwen2.5-7B (ups-fast)
huggingface-cli download Qwen/Qwen2.5-7B-Instruct \
  --local-dir /data/models/Qwen2.5-7B-Instruct

# Qwen2.5-32B-AWQ (ups-main)
huggingface-cli download Qwen/Qwen2.5-32B-Instruct-AWQ \
  --local-dir /data/models/Qwen2.5-32B-Instruct-AWQ

# DeepSeek-R1-Distill-Qwen-32B (ups-reasoner)
huggingface-cli download deepseek-ai/DeepSeek-R1-Distill-Qwen-32B \
  --local-dir /data/models/DeepSeek-R1-Distill-Qwen-32B
```

### 4.4 Configurar variables de entorno

```bash
cp .env.example .env
nano .env
```

Completar los valores obligatorios:

```env
POSTGRES_USER=litellm
POSTGRES_PASSWORD=<contraseña-segura>
POSTGRES_DB=litellm

LITELLM_MASTER_KEY=sk-<clave-aleatoria-larga>
LITELLM_SALT_KEY=<salt-aleatorio>

UI_USERNAME=admin
UI_PASSWORD=<contraseña-panel>

MODELS_PATH=/data/models
```

Generar claves aleatorias:

```bash
openssl rand -hex 32   # usar salida como LITELLM_MASTER_KEY
openssl rand -hex 16   # usar salida como LITELLM_SALT_KEY
```

### 4.5 Levantar la plataforma

```bash
docker compose up -d
```

Los contenedores arrancan en este orden (controlado por `depends_on`):

```
postgres (healthy) ─┐
                     ├─→ litellm → nginx
redis (healthy) ────┘

ups-fast  ─┐
ups-main   ├─→ independientes (vLLM tarda 5-15 min en cargar modelos)
ups-reasoner ┘
```

### 4.6 Monitorear el arranque

```bash
# Ver estado de todos los contenedores
watch docker ps

# Logs de LiteLLM (esperar "Application startup complete")
docker logs -f ups-litellm

# Logs de un modelo vLLM (esperar "Uvicorn running on...")
docker logs -f ups-fast
```

LiteLLM estará listo en ~30-60s.  
Los contenedores vLLM tardan **5-15 minutos** (carga del modelo en GPU).

### 4.7 Verificar la plataforma

```bash
# Health check básico
curl http://localhost/health
# Esperado: "I'm alive!"

# Modelos disponibles
curl http://localhost/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | jq '.data[].id'

# Prueba de inferencia
curl http://localhost/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ups-fast",
    "messages": [{"role": "user", "content": "Responde solo: funcionando"}],
    "max_tokens": 10
  }'
```

O usar el script de healthcheck completo:

```bash
chmod +x scripts/healthcheck.sh
LITELLM_MASTER_KEY=<tu-clave> ./scripts/healthcheck.sh
```

### 4.8 Panel de administración

Abrir en el navegador: `http://<IP-GIGABYTE>/ui`

- **Usuario:** valor de `UI_USERNAME` en `.env`
- **Password:** valor de `UI_PASSWORD` en `.env`

Desde el panel puedes: ver modelos registrados, crear API keys para estudiantes, monitorear uso y costos por usuario.

### 4.9 Crear API keys para estudiantes

```bash
chmod +x scripts/create-user-key.sh
LITELLM_MASTER_KEY=<tu-clave> ./scripts/create-user-key.sh
```

O desde el panel `/ui` → **API Keys** → **Create Key**.

---

## Referencia rápida de comandos

```bash
# Levantar todo
docker compose up -d

# Detener todo
docker compose down

# Ver estado
docker ps
./scripts/healthcheck.sh

# Logs
docker logs ups-litellm -f
docker logs ups-fast -f

# Reiniciar un servicio
docker compose restart litellm

# Activar modelo premium
LITELLM_MASTER_KEY=<clave> ./scripts/start-premium-model.sh

# Desactivar modelo premium
./scripts/stop-premium-model.sh
```

---

## Problemas comunes

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `nvidia-smi` falla tras instalar driver | Secure Boot activo | Deshabilitar en BIOS |
| `Error: no such runtime: nvidia` | Toolkit no configurado | Repetir Paso 3 |
| `CUDA: False` en test vLLM | Driver/toolkit desincronizados | `sudo reboot` |
| LiteLLM en 502 al arrancar | Aún corriendo migraciones | Esperar 30-60s |
| vLLM `OOM` al cargar modelo | VRAM insuficiente | Reducir `--max-model-len` a `16384` |
| vLLM `created` pero no `healthy` | Modelo cargando (normal) | Esperar 5-15 min |
| `curl /health` → 401 | nginx sin actualizar | `docker compose restart nginx` |
