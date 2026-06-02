# Despliegue Fase 1 — UPS AI Platform (Gigabyte)

Guía completa para poner en producción la plataforma desde cero.  
Sistema objetivo: **Ubuntu 24.04.4 LTS** con GPU NVIDIA GB10 (Grace Blackwell).

> **Equipo validado:** NVIDIA GB10 · Driver 580.159.03 · CUDA 13.0 · Memoria unificada CPU+GPU.  
> La GPU GB10 usa arquitectura de memoria unificada — CPU y GPU comparten el mismo pool de RAM,  
> lo que permite cargar modelos más grandes que en GPUs discretas convencionales.

---

## Paso 1 — Validar drivers NVIDIA

```bash
# GPU detectada por el sistema
lspci | grep -i nvidia

# Driver instalado
nvidia-smi
```

**Salida esperada en el equipo Gigabyte (GB10):**

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.159.03             Driver Version: 580.159.03     CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|   0  NVIDIA GB10                    On  |   0000000F:01:00.0 Off |                  N/A |
| N/A   34C    P8              4W /  N/A  | Not Supported          |      0%      Default |
+-----------------------------------------------------------------------------------------+
```

> `Memory-Usage: Not Supported` es normal en el GB10 — usa memoria unificada, no VRAM discreta.

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

# Instalar driver (mínimo 550 para CUDA 12.4+)
sudo apt install -y nvidia-driver-580

# Reiniciar y verificar
sudo reboot
```

> Si usas Ubuntu 22.04 reemplazar `ubuntu2404` por `ubuntu2204` en la URL del keyring.  
> Si `nvidia-smi` falla tras el reinicio, verificar que **Secure Boot esté deshabilitado** en la BIOS.

---

## Paso 2 — Instalar Docker Engine

> **Equipo Gigabyte:** Docker 29.2.1 y Compose v5.0.2 ya estaban instalados — se saltó la instalación.  
> Verificar si ya está antes de instalar:
> ```bash
> docker --version 2>/dev/null && echo "Ya instalado" || echo "No instalado"
> ```

Si no está instalado:

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
```

**En cualquier caso — agregar usuario al grupo docker:**

```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Verificar:**

```bash
docker --version
docker compose version
docker run --rm hello-world
```

Salida esperada (ARM64): mensaje `Hello from Docker!` descargando imagen `arm64v8`.

---

## Paso 3 — Habilitar GPU para Docker (NVIDIA Container Toolkit)

Este componente es el puente entre Docker y el driver NVIDIA del host. Sin él, los contenedores vLLM no pueden acceder a la GPU.

> **Equipo Gigabyte:** nvidia-ctk 1.19.1 ya estaba instalado, pero el runtime NVIDIA **no estaba
> registrado** en Docker. Siempre ejecutar la configuración aunque el toolkit esté instalado.

```bash
# Verificar si ya está instalado
nvidia-ctk --version 2>/dev/null && echo "Ya instalado" || echo "No instalado"

# Si no está instalado, agregar repositorio e instalar:
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# Siempre ejecutar — registra el runtime nvidia en Docker
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

**Verificar que Docker ve la GPU:**

```bash
# Runtime nvidia disponible
docker info | grep -i runtime
```

Salida esperada:
```
Runtimes: io.containerd.runc.v2 nvidia runc
Default Runtime: runc
```

> **Opcional — test de GPU en contenedor** (puede omitirse, la imagen ocupa ~500 MB):
> ```bash
> docker run --rm --gpus all \
>   nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
> # Eliminar imagen después del test:
> docker rmi nvidia/cuda:12.6.0-base-ubuntu24.04
> ```
> La salida debe ser idéntica a `nvidia-smi` en el host. No es necesaria para el despliegue —
> los contenedores vLLM traen su propio entorno CUDA.

---

## Paso 4 — Desplegar Fase 1

### 4.1 Clonar el repositorio

```bash
mkdir -p ~/dgx-workspace
cd ~/dgx-workspace
git clone https://github.com/AppDis/test.git . -b claude/fase1-ups
cd ai-platform
```

### 4.2 Preparar almacenamiento

El equipo tiene un NVMe de 4 TB (SAMSUNG MZALC4T0HBL1). Se crea una partición dedicada
para datos montada en `/data` — separada del sistema operativo, con espacio para modelos
y otros usos futuros (datasets, backups, notebooks, etc.).

```bash
# Corregir tabla GPT para reconocer los 4 TB completos
sudo parted /dev/nvme0n1 print   # responder "Fix" al aviso

# Crear partición con el espacio libre (desde 512 GB hasta el final)
sudo parted -a optimal /dev/nvme0n1 mkpart primary ext4 512GB 100%

# Formatear
sudo mkfs.ext4 /dev/nvme0n1p3

# Montar en /data
sudo mount /dev/nvme0n1p3 /data

# Auto-montar al reiniciar
echo "/dev/nvme0n1p3 /data ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Crear carpeta de modelos y dar permisos al usuario
sudo mkdir -p /data/models
sudo chown $USER:$USER /data
sudo chown $USER:$USER /data/models
```

**Verificar:**
```bash
df -h /data
```

Salida esperada:
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p3  3.3T   28K  3.1T   1% /data
```

Espacio requerido por modelo:

| Modelo | Tamaño |
|--------|--------|
| Qwen2.5-7B-Instruct | ~15 GB |
| Qwen2.5-32B-Instruct-AWQ | ~20 GB |
| DeepSeek-R1-Distill-Qwen-32B | ~65 GB |
| Qwen2.5-72B-Instruct-AWQ (ups-pro) | ~40 GB |

Total mínimo para los 3 modelos base: **~100 GB libres** (disponible: 3.1 TB).

### 4.3 Descargar modelos

> **Nota GB10 (memoria unificada):** el GB10 comparte RAM entre CPU y GPU. Con 128 GB de memoria
> unificada puedes cargar modelos significativamente más grandes que en GPUs discretas convencionales.
> Los modelos AWQ (cuantizados) son la opción recomendada para maximizar el número de modelos activos.

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
