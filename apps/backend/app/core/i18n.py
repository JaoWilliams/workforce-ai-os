import json
from functools import lru_cache
from pathlib import Path
from typing import Optional

from fastapi import Header

SUPPORTED_LOCALES = ("es", "en")
DEFAULT_LOCALE = "es"

I18N_DIR = Path(__file__).resolve().parent.parent / "i18n"


@lru_cache
def _load_catalog(locale: str) -> dict:
    path = I18N_DIR / locale / "messages.json"
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def get_locale(accept_language: Optional[str] = Header(default=None)) -> str:
    if accept_language:
        primary = accept_language.split(",")[0].split("-")[0].strip().lower()
        if primary in SUPPORTED_LOCALES:
            return primary
    return DEFAULT_LOCALE


def translate(key: str, locale: str) -> str:
    catalog = _load_catalog(locale if locale in SUPPORTED_LOCALES else DEFAULT_LOCALE)
    return catalog.get(key, key)
