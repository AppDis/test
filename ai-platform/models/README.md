# Directorio de modelos

Ubicación en el host: valor de `MODELS_PATH` en `.env` (por defecto `/data/models`).

## Estructura esperada

```
/data/models/
├── Qwen2.5-7B-Instruct/          # edu-fast
├── Qwen2.5-32B-Instruct-AWQ/     # edu-main
├── DeepSeek-R1-Distill-Qwen-32B/ # edu-reasoner
├── Qwen2.5-72B-Instruct-AWQ/     # edu-pro (opcional)
└── bge-m3/                        # edu-embed (opcional)
```

## Descarga con huggingface-cli

```bash
pip install huggingface-hub

# edu-fast
huggingface-cli download Qwen/Qwen2.5-7B-Instruct \
  --local-dir /data/models/Qwen2.5-7B-Instruct

# edu-main
huggingface-cli download Qwen/Qwen2.5-32B-Instruct-AWQ \
  --local-dir /data/models/Qwen2.5-32B-Instruct-AWQ

# edu-reasoner
huggingface-cli download deepseek-ai/DeepSeek-R1-Distill-Qwen-32B \
  --local-dir /data/models/DeepSeek-R1-Distill-Qwen-32B

# edu-pro (bajo demanda)
huggingface-cli download Qwen/Qwen2.5-72B-Instruct-AWQ \
  --local-dir /data/models/Qwen2.5-72B-Instruct-AWQ

# edu-embed
huggingface-cli download BAAI/bge-m3 \
  --local-dir /data/models/bge-m3
```
