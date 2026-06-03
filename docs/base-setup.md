# Práctica: Inicialización de Equipo NVIDIA GB10

Guía paso a paso para preparar un servidor de cómputo AI desde cero.  
Cada paso debe ejecutarse, verificarse y comprenderse antes de continuar al siguiente.

**Equipo:** NVIDIA GB10 (Grace Blackwell) · Ubuntu 24.04.4 LTS · ARM64

---

## Paso 1 — Validar drivers NVIDIA

El driver NVIDIA es el componente que permite al sistema operativo comunicarse con la GPU.
Sin él, ningún proceso puede acceder al hardware de cómputo.

### ¿Qué GPU tiene el equipo?

```bash
lspci | grep -i nvidia
```

Esto lista todos los dispositivos PCI fabricados por NVIDIA. El resultado incluye los puentes
PCIe internos del GB10 y la GPU propiamente dicha (línea con `VGA compatible controller`).

### ¿Está el driver instalado?

```bash
nvidia-smi
```

**Salida esperada:**

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.159.03             Driver Version: 580.159.03     CUDA Version: 13.0     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
|   0  NVIDIA GB10                    On  |   0000000F:01:00.0 Off |                  N/A |
| N/A   34C    P8              4W /  N/A  | Not Supported          |      0%      Default |
+-----------------------------------------------------------------------------------------+
```

> **¿Por qué dice `Memory-Usage: Not Supported`?**  
> El GB10 usa **memoria unificada** — CPU y GPU comparten el mismo pool de 128 GB de RAM,
> a diferencia de las GPUs discretas (RTX, A100) que tienen VRAM separada. Por eso
> `nvidia-smi` no puede reportar uso de VRAM: no existe como entidad separada.

> **¿Qué es CUDA?**  
> CUDA es la plataforma de cómputo paralelo de NVIDIA. La versión que aparece (13.0) indica
> el máximo soportado por el driver. Los frameworks de ML (PyTorch, vLLM) usan CUDA para
> ejecutar operaciones matemáticas en la GPU.

Si `nvidia-smi` responde → **continuar al Paso 2**.

Si falla → el driver no está instalado. Instalarlo con:

```bash
# Actualizar el sistema
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential dkms linux-headers-$(uname -r)

# Limpiar cualquier driver anterior
sudo apt purge -y 'nvidia-*' 'libnvidia-*' cuda-drivers 2>/dev/null || true
sudo apt autoremove -y

# Agregar repositorio oficial NVIDIA para Ubuntu 24.04
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update

# Instalar driver
sudo apt install -y nvidia-driver-580

# Reiniciar y verificar
sudo reboot
```

> Si `nvidia-smi` sigue fallando después del reinicio: verificar que **Secure Boot esté
> deshabilitado** en la BIOS/UEFI. El Secure Boot impide cargar módulos del kernel no firmados.

---

## Paso 2 — Instalar Docker Engine

Docker es la plataforma de contenedores que usaremos para ejecutar los servicios de la
plataforma AI de forma aislada y reproducible.

### Verificar si ya está instalado

```bash
docker --version
```

Si responde con una versión → verificar que el usuario tenga permisos y saltar al final de este paso.  
Si no está instalado → seguir los pasos a continuación.

### Limpiar versiones anteriores

```bash
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo apt autoremove -y
```

> Es importante limpiar versiones antiguas para evitar conflictos entre paquetes.

### Instalar dependencias

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg apt-transport-https lsb-release
```

### Agregar el repositorio oficial de Docker

Ubuntu no incluye la versión más reciente de Docker en sus repositorios oficiales.
Hay que agregar el repositorio de Docker Inc. directamente:

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

> **¿Qué hace `$(dpkg --print-architecture)`?**  
> Detecta automáticamente la arquitectura del sistema (en este equipo: `arm64`).
> Así el mismo comando funciona en x86 y ARM sin modificación.

### Instalar Docker

```bash
sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

### Habilitar el servicio

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

### Agregar el usuario al grupo docker

Sin esto, cada comando `docker` requiere `sudo`. Esto ocurre porque el socket de Docker
(`/var/run/docker.sock`) solo es accesible por root y el grupo `docker`.

```bash
sudo usermod -aG docker $USER
newgrp docker
```

> `newgrp docker` abre un nuevo subshell con el grupo activo sin necesidad de cerrar sesión.

### Verificar

```bash
docker --version
docker compose version
docker run --rm hello-world
```

La salida de `hello-world` debe incluir `arm64v8` — confirma que Docker corre nativamente
en ARM64 y no en modo de emulación.

---

## Paso 3 — Habilitar GPU para Docker (NVIDIA Container Toolkit)

Por defecto, los contenedores Docker no tienen acceso a la GPU del host — están aislados
del hardware. El **NVIDIA Container Toolkit** es el puente que permite a los contenedores
acceder al driver NVIDIA instalado en el host.

Sin este componente, los contenedores vLLM no pueden ejecutar inferencia en GPU.

### Verificar si ya está instalado

```bash
nvidia-ctk --version
```

> Aunque el toolkit esté instalado, el runtime puede no estar registrado en Docker.
> **Siempre ejecutar la configuración del runtime** (último bloque de este paso).

### Instalar si no está presente

```bash
# Agregar repositorio NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit
```

### Registrar el runtime nvidia en Docker

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

> Este comando modifica `/etc/docker/daemon.json` para registrar el runtime `nvidia`.
> Sin este paso, el flag `--gpus all` en `docker run` no tiene efecto.

### Verificar

```bash
docker info | grep -i runtime
```

Salida esperada:
```
Runtimes: io.containerd.runc.v2 nvidia runc
Default Runtime: runc
```

La presencia de `nvidia` en la lista confirma que los contenedores pueden solicitar acceso a GPU.

---

## Paso 4 — Preparar almacenamiento

El sistema operativo está instalado en una partición de ~476 GB del NVMe de 4 TB.
Los ~3.5 TB restantes están sin particionar. En este paso se crea una partición dedicada
montada en `/data` para almacenar modelos, datasets y otros datos de la plataforma,
separados del sistema operativo.

> **¿Por qué separar datos del SO?**  
> Si el SO se corrompe o necesita reinstalación, los datos en `/data` quedan intactos.
> También facilita hacer backups selectivos y controlar el espacio independientemente.

### Ver el estado actual del disco

```bash
lsblk /dev/nvme0n1
```

Verás que `nvme0n1p2` (el SO) termina en ~476 GB y el resto del disco aparece sin partición.

### Ver el layout exacto con parted

```bash
sudo parted /dev/nvme0n1 print
```

> Si aparece el aviso *"Not all of the space available..."*, responder `Fix`.
> Esto corrige la tabla GPT para reconocer los 4 TB completos del disco.

### Crear la partición

```bash
sudo parted -a optimal /dev/nvme0n1 mkpart primary ext4 512GB 100%
```

> `512GB` es el punto de inicio (donde termina la partición del SO).  
> `100%` indica que la nueva partición ocupa todo el espacio restante.  
> `-a optimal` alinea la partición al tamaño óptimo de sector del NVMe.

### Formatear con ext4

```bash
sudo mkfs.ext4 /dev/nvme0n1p3
```

> `ext4` es el sistema de archivos estándar de Linux. El proceso crea el journal,
> las tablas de inodos y los superblocks de respaldo.

### Montar en /data

```bash
sudo mount /dev/nvme0n1p3 /data
```

### Configurar montaje automático al reiniciar

```bash
echo "/dev/nvme0n1p3 /data ext4 defaults 0 2" | sudo tee -a /etc/fstab
```

> `/etc/fstab` (filesystem table) es el archivo que el sistema lee al arrancar para
> montar las particiones automáticamente. Sin esta línea, `/data` no se monta tras un reinicio.

### Asignar permisos al usuario

```bash
sudo mkdir -p /data/models
sudo chown -R $USER:$USER /data
```

### Verificar

```bash
df -h /data
```

Salida esperada:
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p3  3.3T   28K  3.1T   1% /data
```

---

## Verificación final del entorno

Ejecuta este bloque para confirmar que todos los pasos están completos:

```bash
echo ""
echo "=== Sistema ==="
lsb_release -d && uname -m

echo ""
echo "=== GPU ==="
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader

echo ""
echo "=== Docker ==="
docker --version
docker compose version

echo ""
echo "=== Runtime NVIDIA en Docker ==="
docker info 2>/dev/null | grep -i runtime

echo ""
echo "=== Almacenamiento /data ==="
df -h /data
```

---

## Preguntas de reflexión

1. ¿Por qué el GB10 muestra `Memory-Usage: Not Supported` en `nvidia-smi`?
2. ¿Qué diferencia hay entre el driver NVIDIA y el NVIDIA Container Toolkit?
3. ¿Por qué se agrega el usuario al grupo `docker` en lugar de usar `sudo` en cada comando?
4. ¿Qué pasaría con los datos en `/data` si se reinstala el sistema operativo?
5. ¿Por qué se usa `$(dpkg --print-architecture)` en lugar de escribir `arm64` directamente?
