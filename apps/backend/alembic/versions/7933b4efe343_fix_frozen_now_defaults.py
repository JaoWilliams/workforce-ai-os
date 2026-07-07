"""fix_frozen_now_defaults

COMENTARIO DE CAMBIOS: corrige el bug donde server_default="now()" (string
plano en SQLAlchemy) se grabó en Postgres como un valor literal CONGELADO
(la hora exacta de cada migración) en vez de la función now() real. Causaba
que audit_logs.created_at, consent_records.granted_at, y los created_at de
tenants/users/branches/roles/user_branches/user_roles repitieran siempre el
mismo timestamp. Ver models.py: ahora usa server_default=text("now()").
Los valores ya insertados con el bug NO se corrigen (son datos de prueba,
no hay forma de recuperar la hora real) — este fix solo aplica hacia adelante.

Revision ID: 7933b4efe343
Revises: 398a1ac5093f
Create Date: 2026-07-07
"""
from alembic import op

revision = "7933b4efe343"
down_revision = "398a1ac5093f"
branch_labels = None
depends_on = None

FIXES = [
    ("tenants", "created_at"),
    ("users", "created_at"),
    ("branches", "created_at"),
    ("roles", "created_at"),
    ("user_branches", "created_at"),
    ("user_roles", "created_at"),
    ("audit_logs", "created_at"),
    ("consent_records", "granted_at"),
]

def upgrade() -> None:
    for table, column in FIXES:
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} SET DEFAULT now();")

def downgrade() -> None:
    # No se restaura el valor literal congelado — era justamente el bug.
    pass
