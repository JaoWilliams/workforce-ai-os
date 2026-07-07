from fastapi import FastAPI

from app.modules.auth.router import router as auth_router
from app.modules.branches.router import router as branches_router

app = FastAPI(title="WORKFORCE AI OS API")

app.include_router(auth_router)
app.include_router(branches_router)


@app.get("/api/health")
def health():
    return {"status": "ok", "service": "workforce-ai-os-api"}
