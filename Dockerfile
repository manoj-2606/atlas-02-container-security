FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install --timeout=60 -r requirements.txt

FROM python:3.12-slim
RUN groupadd -r atlas && useradd -r -g atlas -d /app -s /sbin/nologin atlas
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ ./app/
USER atlas
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]