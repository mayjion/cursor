FROM python:3.12-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOST=0.0.0.0 \
    PORT=8787

COPY pyproject.toml README.md ./
COPY app ./app
COPY config ./config
COPY scripts ./scripts

RUN pip install --no-cache-dir -e . \
 && mkdir -p /app/data

EXPOSE 8787
VOLUME ["/app/data"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8787"]
