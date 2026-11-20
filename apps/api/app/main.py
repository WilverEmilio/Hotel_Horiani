from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.responses import JSONResponse

from .config.base_de_datos import abrir_conexion, cerrar_conexion, conexion_disponible
from .config.entorno import obtener_configuracion

@asynccontextmanager
async def ciclo_de_vida(_: FastAPI):
    conf = obtener_configuracion()
    await abrir_conexion(
        conf.dsn,
        conf.db_pool_min,
        conf.db_pool_max
        )
    try:
        yield
    finally:
        await cerrar_conexion()
        
app = FastAPI(
    title = 'Hotel Horiani API',
    description = 'Esta es la API oficial que se usara en Hotel Horiani',
    version = '1.0.0',
    lifespan = ciclo_de_vida
)

@app.get('/health')
async def health():
    if await conexion_disponible():
        return {
            'status': 'ok',
            'base_de_datos': 'ok'
        }
    return JSONResponse(
        status_code = 503,
        content = {
            'status': 'sin_base_de_datos'
        }
    )