from dataclasses import dataclass


@dataclass(frozen=True)
class SesionEmitida:
    access_token: str
    expira_en: int
    refresh_token: str
    usuario: dict | None = None