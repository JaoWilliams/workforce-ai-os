from fastapi import FastAPI

from app.modules.auth.router import router as auth_router
from app.modules.branches.router import router as branches_router
from app.modules.legal.router import router as legal_router
from app.modules.catalogs.router import router as catalogs_router
from app.modules.catalogs.router import hours_router as catalogs_hours_router
from app.modules.devices.router import router as devices_router
from app.modules.employees.router import router as employees_router
from app.modules.biometrics.router import router as biometrics_router
from app.modules.feature_flags.router import router as feature_flags_router
from app.modules.attendance.router import router as attendance_router
from app.modules.confianza_operativa.router import router as confianza_operativa_router
from app.modules.exceptions.router import router as exceptions_router
from app.modules.shifts.router import router as shifts_router
from app.modules.rbac.router import router as rbac_router
from app.modules.payroll.router import router as payroll_router
from app.modules.accounting.router import router as accounting_router

app = FastAPI(title="WORKFORCE AI OS API")

app.include_router(auth_router)
app.include_router(branches_router)
app.include_router(legal_router)
app.include_router(catalogs_router)
app.include_router(catalogs_hours_router)
app.include_router(devices_router)
app.include_router(employees_router)
app.include_router(biometrics_router)
app.include_router(feature_flags_router)
app.include_router(attendance_router)
app.include_router(confianza_operativa_router)
app.include_router(exceptions_router)
app.include_router(shifts_router)
app.include_router(rbac_router)
app.include_router(payroll_router)
app.include_router(accounting_router)


@app.get("/api/health")
def health():
    return {"status": "ok", "service": "workforce-ai-os-api"}
