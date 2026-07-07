from fastapi import FastAPI

app = FastAPI(title="WORKFORCE AI OS API")


@app.get("/api/health")
def health():
    return {"status": "ok", "service": "workforce-ai-os-api"}
