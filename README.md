# DGX Base Setup — Práctica de Inicialización

Práctica guiada para preparar un equipo **NVIDIA GB10 (Grace Blackwell)** con Ubuntu 24.04,
habilitándolo como nodo de cómputo AI listo para futuras prácticas de la carrera.

## Objetivo

Al completar esta práctica el estudiante habrá:

- Verificado que el hardware GPU está correctamente instalado y operativo
- Instalado y configurado Docker Engine con soporte nativo para GPU
- Preparado el almacenamiento de datos separado del sistema operativo
- Comprendido la arquitectura base de un servidor de inferencia AI

## Equipo de referencia

| Campo | Valor |
|-------|-------|
| GPU | NVIDIA GB10 (Grace Blackwell) |
| Arquitectura | ARM64 (aarch64) |
| Memoria | 128 GB unificada CPU+GPU |
| Almacenamiento | NVMe 4 TB |
| OS | Ubuntu 24.04.4 LTS |

## Pasos

| Paso | Descripción | Tiempo estimado |
|------|-------------|-----------------|
| [1 — Validar drivers NVIDIA](docs/base-setup.md#paso-1--validar-drivers-nvidia) | Verificar que el driver y CUDA están activos | 5 min |
| [2 — Instalar Docker Engine](docs/base-setup.md#paso-2--instalar-docker-engine) | Instalación y configuración de Docker | 10 min |
| [3 — Habilitar GPU para Docker](docs/base-setup.md#paso-3--habilitar-gpu-para-docker-nvidia-container-toolkit) | NVIDIA Container Toolkit + runtime | 10 min |
| [4 — Preparar almacenamiento](docs/base-setup.md#paso-4--preparar-almacenamiento) | Partición dedicada montada en /data | 10 min |

**Guía completa:** [`docs/base-setup.md`](docs/base-setup.md)

---

> Una vez completada esta práctica, el equipo queda listo para el despliegue de la plataforma AI:  
> [`claude/fase1-ups`](https://github.com/AppDis/test/tree/claude/fase1-ups)
