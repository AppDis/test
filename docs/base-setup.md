# Base Setup — NVIDIA GB10 / Ubuntu 24.04

Guía paso a paso para preparar el equipo antes de desplegar cualquier plataforma AI.

> **Equipo validado:** NVIDIA GB10 · Driver 580.159.03 · CUDA 13.0 · Ubuntu 24.04.4 LTS · ARM64

---

## Paso 1 — Validar drivers NVIDIA

```bash
lspci | grep -i nvidia
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

> `Memory-Usage: Not Supported` es normal — el GB10 usa memoria unificada CPU+GPU.

Si `nvidia-smi` responde → **saltar al Paso 2**.  
Si falla → instalar el driver:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential dkms linux-headers-$(uname -r)
sudo apt purge -y 'nvidia-*' 'libnvidia-*' cuda-drivers 2>/dev/null || true
sudo apt autoremove -y

# Repositorio NVIDIA (Ubuntu 24.04 / ARM64)
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y nvidia-driver-580
sudo reboot
```

> Si `nvidia-smi` falla tras el reinicio: verificar que **Secure Boot esté deshabilitado** en BIOS.

---

## Paso 2 — Instalar Docker Engine

Verificar si ya está instalado:

```bash
docker --version 2>/dev/null && echo "Ya instalado" || echo "No instalado"
```

> **Equipo Gigabyte:** Docker 29.2.1 ya estaba instalado. Saltar a "Agregar usuario al grupo docker".

Si no está instalado:

```bash
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo apt autoremove -y
sudo apt update
sudo apt install -y ca-certificates curl gnupg apt-transport-https lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker
```

**Agregar usuario al grupo docker (siempre):**

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

Salida esperada (ARM64): `Hello from Docker!` descargando imagen `arm64v8`.

---

## Paso 3 — Habilitar GPU para Docker (NVIDIA Container Toolkit)

> **Equipo Gigabyte:** nvidia-ctk 1.19.1 ya estaba instalado, pero el runtime no estaba registrado.  
> Siempre ejecutar la configuración del runtime aunque el toolkit esté instalado.

```bash
# Verificar si ya está instalado
nvidia-ctk --version 2>/dev/null && echo "Ya instalado" || echo "No instalado"

# Si no está instalado:
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

**Verificar:**

```bash
docker info | grep -i runtime
```

Salida esperada:
```
Runtimes: io.containerd.runc.v2 nvidia runc
Default Runtime: runc
```

---

## Paso 4 — Preparar almacenamiento

El equipo tiene un NVMe de 4 TB (SAMSUNG MZALC4T0HBL1). Se crea una partición dedicada
montada en `/data` — separada del SO, reutilizable para modelos, datasets, backups, etc.

```bash
# Ver layout del disco (responder "Fix" al aviso de GPT)
sudo parted /dev/nvme0n1 print

# Crear partición con el espacio libre (desde 512 GB hasta el final)
sudo parted -a optimal /dev/nvme0n1 mkpart primary ext4 512GB 100%

# Formatear
sudo mkfs.ext4 /dev/nvme0n1p3

# Montar en /data
sudo mount /dev/nvme0n1p3 /data

# Auto-montar al reiniciar
echo "/dev/nvme0n1p3 /data ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Permisos al usuario
sudo chown -R $USER:$USER /data
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

---

## Verificación final

```bash
echo "=== OS ===" && lsb_release -a
echo "=== Arch ===" && uname -m
echo "=== GPU ===" && nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader
echo "=== Docker ===" && docker --version && docker compose version
echo "=== Runtime NVIDIA ===" && docker info | grep -i nvidia
echo "=== Almacenamiento ===" && df -h /data
```

---

## Problemas comunes

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `nvidia-smi` falla tras instalar driver | Secure Boot activo | Deshabilitar en BIOS |
| `Error: no such runtime: nvidia` | Runtime no configurado | Repetir Paso 3 |
| `permission denied /var/run/docker.sock` | Usuario no en grupo docker | Repetir `usermod` y abrir nueva terminal |
| `/data` sin permisos | `chown` no ejecutado | `sudo chown -R $USER:$USER /data` |
