import os
import time
from fastapi import FastAPI, Query
from fastapi.responses import PlainTextResponse
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from app.metrics import REQUEST_COUNT, REQUEST_LATENCY
from app.simulator import simulate_failure, simulate_load

app = FastAPI(title="Atlas Platform App", version="1.0.0")

@app.middleware("http")
async def track_metrics(request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start

    endpoint = request.url.path
    method = request.method
    status = str(response.status_code)

    REQUEST_COUNT.labels(method=method, endpoint=endpoint, status=status).inc()
    REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(duration)

    return response

@app.get("/health")
async def health():
    return {"status": "healthy", "version": "1.0.0"}

@app.get("/info")
async def info():
    return {
        "app": "atlas-platform-app",
        "env": os.getenv("APP_ENV", "dev")
    }

@app.get("/metrics", response_class=PlainTextResponse)
async def metrics():
    return PlainTextResponse(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )

@app.post("/simulate/failure")
async def failure(mode: str = Query(default="crash", enum=["crash", "oom", "slow"])):
    result = simulate_failure(mode)
    return result or {"status": f"{mode} triggered"}

@app.post("/simulate/load")
async def load(duration: int = Query(default=30, ge=5, le=300), cpu_percent: int = Query(default=80, ge=10, le=100)):
    return simulate_load(duration, cpu_percent)