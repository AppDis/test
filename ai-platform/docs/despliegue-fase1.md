# Despliegue Fase 1 — UPS AI Platform (Gigabyte)

Guía completa para poner en producción la plataforma desde cero.  
Sistema objetivo: **Ubuntu 24.04.4 LTS** con GPU NVIDIA GB10 (Grace Blackwell).

> **Equipo validado:** NVIDIA GB10 · Driver 580.159.03 · CUDA 13.0 · Memoria unificada CPU+GPU.  
> La GPU GB10 usa arquitectura de memoria unificada — CPU y GPU comparten el mismo pool de RAM
> (121.69 GiB disponibles en producción).  
>
> **Límite real de memoria en GB10:** los 3 modelos BF16 juntos (7B + 32B-AWQ + 32B BF16) requieren
> ~124 GB y **no caben simultáneamente** en 121 GB. La configuración por defecto arranca
> `ups-fast` + `ups-main` (modo normal). `ups-reasoner` es on-demand y requiere detener `ups-main`
> primero — ver [Paso 5.9](#paso-59--cambio-de-modo-on-demand).

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

## Paso 4 — Preparar almacenamiento

El equipo tiene un NVMe de 4 TB (SAMSUNG MZALC4T0HBL1). Se crea una partición dedicada
montada en `/data` — separada del sistema operativo, con espacio para modelos y otros usos
futuros (datasets, backups, notebooks, etc.).

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

---

## Paso 5 — Desplegar Fase 1

### 5.1 Clonar el repositorio

```bash
mkdir -p ~/dgx-workspace
cd ~/dgx-workspace
git clone https://github.com/AppDis/test.git . -b claude/fase1-ups
cd ai-platform
```

### 5.2 Descargar modelos

> **Nota GB10 (memoria unificada):** el GB10 comparte RAM entre CPU y GPU. Con 128 GB de memoria
> unificada puedes cargar modelos más grandes que en GPUs discretas convencionales.
> Los modelos AWQ (cuantizados) son la opción recomendada para maximizar el número de modelos activos.

```bash
# Instalar hf (huggingface-hub) — Ubuntu 24.04 requiere pipx
sudo apt install -y pipx
pipx install huggingface-hub
pipx ensurepath
source ~/.bashrc   # o abrir nueva terminal

# Verificar
hf --version
```

> En Ubuntu 24.04 no usar `pip install` directo — el sistema está externally-managed.  
> El comando es `hf` (no `huggingface-cli`, que está deprecado desde v1.17+).

```bash
# Qwen2.5-7B (ups-fast) ~15 GB
hf download Qwen/Qwen2.5-7B-Instruct \
  --local-dir /data/models/Qwen2.5-7B-Instruct

# Qwen2.5-32B-AWQ (ups-main) ~20 GB
hf download Qwen/Qwen2.5-32B-Instruct-AWQ \
  --local-dir /data/models/Qwen2.5-32B-Instruct-AWQ

# DeepSeek-R1-Distill-Qwen-32B (ups-reasoner) ~65 GB
hf download deepseek-ai/DeepSeek-R1-Distill-Qwen-32B \
  --local-dir /data/models/DeepSeek-R1-Distill-Qwen-32B
```

### 5.3 Configurar variables de entorno

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

### 5.4 Levantar la plataforma

```bash
docker compose up -d
```

> **Nota GB10:** `ups-reasoner` tiene `profiles: [reasoning]` y **no arranca** con este comando.
> Modo por defecto: `ups-fast` + `ups-main` activos.

Los contenedores arrancan en este orden (controlado por `depends_on`):

```
postgres (healthy) ─┐
                     ├─→ litellm → nginx
redis (healthy) ────┘

ups-fast  ─┬─→ independientes (vLLM tarda 5-15 min en cargar modelos en GPU)
ups-main  ─┘
```

**Salida esperada al ejecutar (primera vez — descarga imágenes):**

```
✔ redis Pulled
✔ postgres Pulled
✔ litellm Pulled
✔ ups-fast Pulled     # imagen ARM64 ~11 GB: vllm/vllm-openai:latest-aarch64-cu129-ubuntu2404
✔ ups-main Pulled
[+] Running 7/7
 ✔ Container ups-postgres  Healthy
 ✔ Container ups-redis     Healthy
 ✔ Container ups-litellm   Started
 ✔ Container ups-nginx     Started
 ✔ Container ups-fast      Started
 ✔ Container ups-main      Started
```

### 5.5 Monitorear el arranque

```bash
# Ver estado de todos los contenedores
watch docker ps

# Logs de LiteLLM (primera vez: ~109 migraciones Prisma, luego "Application startup complete")
docker logs -f ups-litellm

# Logs de un modelo vLLM (esperar "Uvicorn running on http://0.0.0.0:8000")
docker logs -f ups-fast
docker logs -f ups-main
```

**Tiempos reales en el GB10:**

| Servicio | Tiempo hasta healthy |
|----------|---------------------|
| postgres | ~5 s |
| redis | ~3 s |
| litellm | ~60 s (primera vez: 109 migraciones Prisma) |
| nginx | ~15 s |
| ups-fast (7B) | ~3-5 min |
| ups-main (32B AWQ) | ~10-12 min |

**Estado esperado cuando todo está listo:**

```
CONTAINER ID   IMAGE                                          STATUS
ups-nginx      nginx:alpine                                   Up X min (healthy)
ups-litellm    ghcr.io/berriai/litellm:main-latest            Up X min
ups-fast       vllm/vllm-openai:latest-aarch64-cu129-...     Up X min (healthy)
ups-main       vllm/vllm-openai:latest-aarch64-cu129-...     Up X min (healthy)
ups-postgres   postgres:16-alpine                             Up X min (healthy)
ups-redis      redis:7-alpine                                 Up X min (healthy)
```

### 5.6 Verificar la plataforma

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

### 5.7 Panel de administración

Abrir en el navegador: `http://<IP-GIGABYTE>/ui`

- **Usuario:** valor de `UI_USERNAME` en `.env`
- **Password:** valor de `UI_PASSWORD` en `.env`

Desde el panel puedes: ver modelos registrados, crear API keys para estudiantes, monitorear uso y costos por usuario.

### 5.8 Crear API keys para estudiantes

```bash
chmod +x scripts/create-user-key.sh
LITELLM_MASTER_KEY=<tu-clave> ./scripts/create-user-key.sh
```

O desde el panel `/ui` → **API Keys** → **Create Key**.

### 5.8.1 Usar el chat integrado del panel (`/ui/chat`)

El chat en `/ui/chat` requiere autenticación con una API key de LiteLLM (distinta de la contraseña del panel).

**Pasos en LiteLLM v1.82.6:**

1. Ir a `http://<IP>/ui` → iniciar sesión con `UI_USERNAME` / `UI_PASSWORD`
2. En el menú lateral: **API Keys** → **Create Key**
3. Crear una key (puede ser la master key `LITELLM_MASTER_KEY` o una nueva)
4. En `/ui/chat`: hacer clic en el icono de engranaje (⚙️) en la esquina superior derecha
5. En **API Key** pegar la clave creada → guardar
6. Seleccionar modelo (`ups-fast`, `ups-main`) y enviar mensaje

> **Nota:** La sección "Credentials" del panel es para conexiones OAuth de servidores MCP,
> **no** para la autenticación del chat. El campo de API key del chat está en el engranaje (⚙️).

**Verificar API directamente (sin UI):**

```bash
curl http://<IP-GIGABYTE>/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ups-fast",
    "messages": [{"role": "user", "content": "Di solo: funcionando"}],
    "max_tokens": 10
  }'
```

### 5.9 — Cambio de modo on-demand

Por limitación de memoria del GB10 (121 GB), `ups-reasoner` (DeepSeek-R1 32B BF16, ~77 GB) no puede
correr junto con `ups-main` (32B AWQ, ~22 GB). Se intercambian on-demand:

**Activar modo razonador** (detiene ups-main, levanta ups-reasoner):

```bash
chmod +x scripts/start-reasoner.sh
LITELLM_MASTER_KEY=<clave> ./scripts/start-reasoner.sh
```

El script espera hasta que ups-reasoner esté listo (~5-15 min) y lo registra en LiteLLM automáticamente.

**Restaurar modo normal** (detiene ups-reasoner, levanta ups-main):

```bash
./scripts/stop-reasoner.sh
```

**Activar modelo premium ups-pro** (72B AWQ, requiere detener otros modelos):

```bash
LITELLM_MASTER_KEY=<clave> ./scripts/start-premium-model.sh
```

**Tabla de modos de operación:**

| Modo | Activos | Memoria aprox. | Comando |
|------|---------|----------------|---------|
| Normal (defecto) | ups-fast + ups-main | ~37 GB | `docker compose up -d` |
| Razonador | ups-fast + ups-reasoner | ~92 GB | `scripts/start-reasoner.sh` |
| Premium | ups-fast + ups-pro | ~57 GB | `scripts/start-premium-model.sh` |

---

## Referencia rápida de comandos

```bash
# Levantar todo (modo normal: ups-fast + ups-main)
docker compose up -d

# Detener todo
docker compose down

# Ver estado
docker ps
./scripts/healthcheck.sh

# Logs
docker logs ups-litellm -f
docker logs ups-fast -f
docker logs ups-main -f

# Reiniciar un servicio
docker compose restart litellm

# Modo razonador (ups-fast + ups-reasoner, detiene ups-main)
LITELLM_MASTER_KEY=<clave> ./scripts/start-reasoner.sh
./scripts/stop-reasoner.sh          # volver al modo normal

# Activar modelo premium
LITELLM_MASTER_KEY=<clave> ./scripts/start-premium-model.sh

# Detener un modelo específico sin bajar todo
docker compose stop ups-main
docker compose up -d ups-main       # volver a levantar
```

---

## Problemas comunes

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `nvidia-smi` falla tras instalar driver | Secure Boot activo | Deshabilitar en BIOS |
| `Error: no such runtime: nvidia` | Toolkit no configurado | Repetir Paso 3 |
| `CUDA: False` en test vLLM | Driver/toolkit desincronizados | `sudo reboot` |
| LiteLLM en 502 al arrancar | Aún corriendo migraciones | Esperar 30-60s |
| vLLM `OOM` — `Free memory X/121.69 GiB` | `gpu_memory_utilization` muy alto | Ya configurado por modelo en `docker-compose.yml`; si persiste, reducir el valor |
| ups-main en crash loop junto a ups-reasoner | 3 modelos BF16 no caben en 121 GB | Usar `scripts/start-reasoner.sh` (detiene ups-main automáticamente) |
| vLLM `created` pero no `healthy` | Modelo cargando (normal) | Esperar 5-15 min |
| nginx `unhealthy` en Alpine | `localhost` resuelve a `::1` (IPv6) | Ya corregido: healthcheck usa `127.0.0.1` |
| Chat `/ui/chat` no responde | API key no configurada en UI | Ver Paso 5.8.1 — engranaje ⚙️ en `/ui/chat` |
| `curl /health` → 401 | nginx sin actualizar | `docker compose restart nginx` |
