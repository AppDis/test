# Instalación de Docker Engine + NVIDIA Container Toolkit en Ubuntu

Guía para preparar el equipo con GPU NVIDIA antes de levantar la plataforma.

---

## Requisitos previos

- Ubuntu 22.04 LTS o 24.04 LTS
- Driver NVIDIA instalado y funcionando (`nvidia-smi` responde)
- Acceso a Internet
- Usuario con permisos `sudo`

---

## Paso 1 — Limpiar versiones anteriores

```bash
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo apt autoremove -y
```

---

## Paso 2 — Instalar dependencias

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg apt-transport-https lsb-release
```

---

## Paso 3 — Agregar repositorio oficial de Docker

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

---

## Paso 4 — Instalar Docker Engine

```bash
sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

---

## Paso 5 — Habilitar y arrancar el servicio

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

---

## Paso 6 — Agregar el usuario al grupo docker

Sin esto, cada comando `docker` requiere `sudo`.

```bash
sudo usermod -aG docker $USER
newgrp docker
```

---

## Paso 7 — Verificar Docker

```bash
docker --version
docker compose version
docker run --rm hello-world
```

Salida esperada al final: `Hello from Docker!`

---

## Paso 8 — Instalar NVIDIA Container Toolkit

Permite que los contenedores accedan a la GPU del host.

```bash
# Agregar repositorio
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configurar el runtime NVIDIA en Docker
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

---

## Paso 9 — Prueba final: GPU dentro de contenedor

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

Si aparece la tabla con los datos de la GPU → instalación completa y correcta.

---

## Problemas comunes

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| `docker: command not found` | Instalación incompleta | Repetir pasos 3 y 4 |
| `permission denied /var/run/docker.sock` | Usuario no en grupo docker | Repetir paso 6 y cerrar/abrir sesión |
| `docker: Error no such runtime: nvidia` | Toolkit no configurado | Repetir paso 8 |
| `Failed to initialize NVML` | Driver no cargado | Verificar `nvidia-smi` en el host |
| GPU no visible en contenedor | Toolkit instalado antes del driver | Reinstalar toolkit después del driver |

---

## Script automatizado

Para ejecutar todo en un solo paso usar el script incluido:

```bash
chmod +x scripts/setup-docker.sh
sudo ./scripts/setup-docker.sh
```
