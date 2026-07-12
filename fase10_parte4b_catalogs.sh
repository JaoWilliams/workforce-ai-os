#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 4b: catalogo BankFileConfig
# ============================================================
# Mismo patron singleton-por-tenant que CesantiaConfig/AguinaldoConfig:
# PUT/GET /api/catalogs/bank-file-config. Guarda la glosa real de
# transferencia bancaria (no hardcodeada).
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte4b_catalogs.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/backend/app/modules/catalogs/schemas.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

if "BankFileConfigUpsert" in src:
    print("SKIP: catalogs/schemas.py ya tiene BankFileConfigUpsert (idempotente)")
else:
    anchor = '''class ChartOfAccountResponse(BaseModel):
    id: UUID
    code: str
    name: str
    account_type: str
    active: bool'''
    assert anchor in src, "ANCHOR NOT FOUND: ChartOfAccountResponse"
    assert src.count(anchor) == 1, "ANCHOR NOT UNIQUE: ChartOfAccountResponse"
    new = anchor + '''
class BankFileConfigUpsert(BaseModel):
    glosa: str
class BankFileConfigResponse(BaseModel):
    glosa: str
    active: bool'''
    src = src.replace(anchor, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("OK: catalogs/schemas.py actualizado (BankFileConfigUpsert/Response)")
PYEOF

python3 << 'PYEOF'
path = "apps/backend/app/modules/catalogs/router.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

if "BankFileConfig" in src:
    print("SKIP: catalogs/router.py ya tiene BankFileConfig (idempotente)")
else:
    anchor_model_import = "from app.db.models import AguinaldoConfig, CesantiaConfig, CesantiaScaleRow, ChartOfAccount, Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, TaxBracket, User, VacationConfig"
    assert anchor_model_import in src, "ANCHOR NOT FOUND: model import line"
    assert src.count(anchor_model_import) == 1, "ANCHOR NOT UNIQUE: model import line"
    new_model_import = "from app.db.models import AguinaldoConfig, BankFileConfig, CesantiaConfig, CesantiaScaleRow, ChartOfAccount, Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, TaxBracket, User, VacationConfig"
    src = src.replace(anchor_model_import, new_model_import)

    anchor_schema_import = "    ChartOfAccountCreate,\n    ChartOfAccountUpdate,\n    ChartOfAccountResponse,\n)"
    assert anchor_schema_import in src, "ANCHOR NOT FOUND: schema import block tail"
    assert src.count(anchor_schema_import) == 1, "ANCHOR NOT UNIQUE: schema import block tail"
    new_schema_import = "    ChartOfAccountCreate,\n    ChartOfAccountUpdate,\n    ChartOfAccountResponse,\n    BankFileConfigUpsert,\n    BankFileConfigResponse,\n)"
    src = src.replace(anchor_schema_import, new_schema_import)

    # Endpoints nuevos al final del archivo
    src = src.rstrip("\n") + '''


@hours_router.put("/bank-file-config", response_model=BankFileConfigResponse)
async def upsert_bank_file_config(
    payload: BankFileConfigUpsert,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(BankFileConfig))
        config = result.scalars().first()
        if config is None:
            config = BankFileConfig(id=uuid4(), tenant_id=current_user.tenant_id, glosa=payload.glosa, active=True)
            session.add(config)
            action = "bank_file_config.created"
        else:
            config.glosa = payload.glosa
            action = "bank_file_config.updated"
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=action, resource_type="bank_file_config", resource_id=None,
            extra={"glosa": payload.glosa},
        )
        await session.commit()
        await session.refresh(config)
    return BankFileConfigResponse(glosa=config.glosa, active=config.active)


@hours_router.get("/bank-file-config", response_model=Optional[BankFileConfigResponse])
async def get_bank_file_config(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(BankFileConfig))
        config = result.scalars().first()
    if config is None:
        return None
    return BankFileConfigResponse(glosa=config.glosa, active=config.active)
'''
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("OK: catalogs/router.py actualizado (endpoints bank-file-config)")
PYEOF

python3 -m py_compile apps/backend/app/modules/catalogs/schemas.py apps/backend/app/modules/catalogs/router.py && echo "SYNTAX OK: catalogs schemas.py + router.py"

echo "=== FIN Parte 4b (catalogo BankFileConfig) ==="
