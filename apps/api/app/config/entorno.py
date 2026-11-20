from functools import lru_cache
from pathlib import Path
from typing import Literal

from psycopg.conninfo import make_conninfo
from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

RAIZ_REPO = Path(__file__).resolve().parents[4]

class Configuracion(BaseSettings):
    model_config = SettingsConfigDict(
        env_file = RAIZ_REPO / '.env',
        env_file_encoding = 'utf-8', 
        extra = 'ignore',
    )
    
    entorno: Literal['desarrollo', 'produccion', 'pruebas'] = 'desarrollo'
    
    db_host: str = '127.0.0.1'
    postgres_port: int = 5432
    postgres_db: str = 'hotel_horiani'
    api_db_user: str
    api_db_password: SecretStr
    db_pool_min: int = 2
    db_pool_max: int = 10
    
    origenes_cors: str = "http://localhost:4321,http://localhost:5173"
    
    @property
    def dsn(self) -> str: 
        return make_conninfo(
            host = self.db_host,
            port = self.postgres_port,
            dbname = self.postgres_db,
            user = self.api_db_user,
            password = self.api_db_password.get_secret_value(),
            application_name = 'horiani_api',
        )
        
    @property
    def lista_origenes(self) -> list[str]:
        return [o.strip().rstrip("/") for o in self.origenes_cors.split(",") if o.strip()]

    @property
    def es_desarrollo(self) -> bool:
        return self.entorno in ("desarrollo", "pruebas")
        
@lru_cache
def obtener_configuracion() -> Configuracion:
    return Configuracion() 
    