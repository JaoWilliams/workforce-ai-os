from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    redis_url: str
    postgres_db: str = "workforce_ai_os"
    postgres_user: str = "workforce"
    postgres_password: str

    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60

    # Umbral heurístico del Motor de Confianza Operativa™ (mód. 17a): si un
    # empleado marca en dos sucursales distintas con menos de este margen
    # entre marcaciones, se considera un patrón físicamente imposible.
    # Configurable por env var (no hardcodeado) — se ajusta según feedback
    # real del piloto, sin necesidad de tocar código.
    confianza_impossible_travel_minutes: int = 30


@lru_cache
def get_settings() -> Settings:
    return Settings()
