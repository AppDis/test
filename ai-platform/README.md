# AI Platform — Carrera de Computación

Plataforma local de IA para estudiantes de Sistemas Distribuidos.  
API compatible con OpenAI, control por API Key, observabilidad completa.

---

## Requisitos previos del host

```bash
# 1. NVIDIA Driver
nvidia-smi

# 2. Docker Engine
docker --version

# 3. NVIDIA Container Toolkit
nvidia-ctk --version

# 4. Validar GPU en contenedor
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

---

## Despliegue inicial

### 1. Clonar y configurar

```bash
git clone <repo-url> ai-platform
cd ai-platform

cp .env.example .env
# Editar .env: contraseñas, dominio, MODELS_PATH
nano .env
```

### 2. Descargar modelos

Ver `models/README.md` para instrucciones de descarga con `huggingface-cli`.

### 3. Exposición pública con Cloudflare Tunnel

No se necesita certificado TLS local, ni abrir puertos 80/443, ni coordinar
firewall con el Departamento de Sistemas: `nginx` no publica ningún puerto en
el host, y el contenedor `cloudflared` lo expone a Internet mediante un túnel
saliente. Cloudflare termina el TLS público.

1. En el [dashboard de Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
   (requiere el dominio ya administrado por Cloudflare):
   `Networks → Tunnels → Create a tunnel → Cloudflared → Docker`.
2. Copia el token que te da el asistente (empieza con `eyJ...`) y ponlo en `.env`:
   ```
   CLOUDFLARE_TUNNEL_TOKEN=eyJ...
   ```
3. En la pestaña **Public Hostname** del túnel, agrega una ruta:
   - Subdomain: `ia-computacion` (o el que asigne Sistemas)
   - Domain: tu dominio institucional en Cloudflare
   - Service: `HTTP` → `nginx:80`
4. (Opcional) Si quieres restringir el panel `/ui` a cuentas autorizadas
   además del login de LiteLLM, crea una **Cloudflare Access Application**
   apuntando al mismo hostname + path `/ui*`, con política de email/dominio
   institucional.

### 4. Levantar la plataforma

```bash
docker compose up -d
```

### 5. Verificar estado

```bash
# Variables de entorno necesarias para el script
source .env
export LITELLM_MASTER_KEY

./scripts/healthcheck.sh
```

---

## Gestión de API Keys

### Crear key para un estudiante

```bash
source .env
export LITELLM_MASTER_KEY

./scripts/create-user-key.sh estudiante@institucion.edu.ec
# Con modelos específicos:
./scripts/create-user-key.sh estudiante@institucion.edu.ec edu-fast,edu-main
```

### Listar keys existentes

```bash
curl http://localhost:4000/key/list \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq .
```

### Revocar una key

```bash
curl -X DELETE http://localhost:4000/key/delete \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"keys": ["sk-la-key-a-revocar"]}'
```

---

## Uso de la API (ejemplo para estudiantes)

```bash
# Con la API Key asignada por el administrador
export API_KEY="sk-tu-api-key"
export API_BASE="https://ia-computacion.example.edu.ec/v1"

# Listar modelos disponibles
curl $API_BASE/models -H "Authorization: Bearer $API_KEY"

# Chat
curl $API_BASE/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "edu-main",
    "messages": [{"role": "user", "content": "Explica qué es un sistema distribuido."}]
  }'
```

Compatible con cualquier cliente OpenAI: Python SDK, LangChain, LlamaIndex, etc.

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-tu-api-key",
    base_url="https://ia-computacion.example.edu.ec/v1"
)

response = client.chat.completions.create(
    model="edu-main",
    messages=[{"role": "user", "content": "Explica qué es un sistema distribuido."}]
)
print(response.choices[0].message.content)
```

---

## Modelo premium (edu-pro)

El modelo premium **no se inicia automáticamente**.

```bash
# Iniciar para sesión de prueba
./scripts/start-premium-model.sh

# Detener al terminar
./scripts/stop-premium-model.sh
```

---

## Observabilidad

| Servicio      | URL interna               | Notas                              |
|---------------|---------------------------|------------------------------------|
| Grafana       | https://dominio/grafana   | Admin: ver `.env`                  |
| LiteLLM UI    | https://dominio/litellm   | Panel de administración            |
| Prometheus    | Solo interno (9090)       | No exponer a Internet              |
| Alertmanager  | Solo interno (9093)       | Configurar receptor en `alertmanager.yml` |

---

## Modelos disponibles

| Alias          | Modelo base                      | Uso                             |
|----------------|----------------------------------|---------------------------------|
| `edu-fast`     | Qwen2.5-7B-Instruct              | Consultas rápidas               |
| `edu-main`     | Qwen2.5-32B-Instruct-AWQ         | Asistente académico general     |
| `edu-reasoner` | DeepSeek-R1-Distill-Qwen-32B     | Razonamiento y análisis         |
| `edu-pro`      | Qwen2.5-72B-Instruct-AWQ         | Premium / bajo demanda          |
| `edu-embed`    | bge-m3                           | Embeddings / RAG                |

---

## Comandos útiles

```bash
# Ver logs de un servicio
docker compose logs -f litellm
docker compose logs -f edu-main

# Estado de todos los contenedores
docker compose ps

# Reiniciar un servicio
docker compose restart edu-fast

# Actualizar imágenes
docker compose pull
docker compose up -d

# Ver uso de GPU en tiempo real
watch -n 2 nvidia-smi
```

---

## Fases de implementación

| Fase | Descripción                        | Duración estimada         |
|------|------------------------------------|---------------------------|
| 1    | Configuración inicial y drivers    | 1 semana                  |
| 2    | Plataforma de servicios            | 1 semana                  |
| 3    | Observabilidad                     | 1 semana                  |
| 4    | Publicación institucional          | Depende de Dpto. Sistemas |
| 5    | Piloto académico                   | 2 meses                   |

---

## Coordinación con Departamento de Sistemas

Con Cloudflare Tunnel ya no es necesario abrir puertos ni gestionar
certificados: el túnel sale desde el contenedor `cloudflared` y no requiere
ninguna regla de firewall entrante. Requerimientos para publicación:

- Subdominio institucional gestionado en Cloudflare (DNS ya delegado/proxied)
- Token del túnel (`CLOUDFLARE_TUNNEL_TOKEN`) generado en Zero Trust
- Revisión de seguridad perimetral / política de acceso (opcional: Cloudflare Access sobre `/ui`)
