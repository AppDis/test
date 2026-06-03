# DGX Base Setup

Preparación base para equipos **NVIDIA GB10 (Grace Blackwell)** con Ubuntu 24.04.  
Prerequisito para cualquier despliegue de plataforma AI sobre Docker.

## Qué incluye

| Paso | Descripción |
|------|-------------|
| 1 | Validar drivers NVIDIA |
| 2 | Instalar Docker Engine |
| 3 | Habilitar GPU para Docker (NVIDIA Container Toolkit) |
| 4 | Preparar almacenamiento (partición dedicada /data) |

## Equipo de referencia

| Campo | Valor |
|-------|-------|
| GPU | NVIDIA GB10 (Grace Blackwell) |
| Driver | 580.159.03 |
| CUDA | 13.0 |
| Arquitectura | ARM64 (aarch64) |
| Memoria | 128 GB unificada CPU+GPU |
| Almacenamiento | NVMe 4 TB (SAMSUNG MZALC4T0HBL1) |
| OS | Ubuntu 24.04.4 LTS |

## Uso rápido

```bash
# Clonar este branch
git clone https://github.com/AppDis/test.git -b dgx-base-setup dgx-base
cd dgx-base

# Ejecutar setup automatizado (Pasos 2, 3 y 4)
chmod +x scripts/setup.sh
sudo ./scripts/setup.sh
```

## Uso manual

Ver guía completa en [`docs/base-setup.md`](docs/base-setup.md).

---

> Una vez completado este setup, continuar con el despliegue de la plataforma:  
> [`claude/fase1-ups`](https://github.com/AppDis/test/tree/claude/fase1-ups)
