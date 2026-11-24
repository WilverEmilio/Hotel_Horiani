from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config.base_de_datos import conexion_disponible
from .config.entorno import obtener_configuracion
from .modulos.autenticacion.rutas.autenticacion_rutas import rutas_autenticacion
from .modulos.habitaciones.rutas.habitacioens_rutas import rutas_habitaciones
from .modulos.habitaciones.rutas.tipos_habitacion_rutas import (
    rutas_tipos_habitacion,
    rutas_tipos_habitacion_publico,
)
from .modulos.hoteles.rutas.hoteles_rutas import rutas_hoteles, rutas_hoteles_publico
from .modulos.reservaciones.rutas.reservaciones_rutas import (
    rutas_disponibilidad_publico,
    rutas_reservaciones,
)
from .modulos.usuarios.rutas.usuarios_rutas import rutas_usuarios
from .shared.middleware.contexto import contexto_peticion
from .shared.middleware.manejo_errores import registrar_manejo_errores

RUTAS = [
    rutas_hoteles_publico,
    rutas_autenticacion,
    rutas_usuarios,
    rutas_hoteles,
    rutas_habitaciones,
    rutas_tipos_habitacion,
    rutas_tipos_habitacion_publico,
    rutas_disponibilidad_publico,
    rutas_reservaciones,
]


def crear_aplicacion(ciclo_de_vida=None) -> FastAPI:
    conf = obtener_configuracion()
    app = FastAPI(
        title="Hotel Horiani API",
        version="1.0.0",
        description="API del sistema Hotel Horiani. Todo el acceso a datos es por stored procedures.",
        lifespan=ciclo_de_vida,
        docs_url="/docs" if conf.es_desarrollo else None,  
        redoc_url=None,
        openapi_url="/openapi.json" if conf.es_desarrollo else None,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=conf.lista_origenes,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Cliente"],
    )

    registrar_manejo_errores(app)
    
    app.middleware('http')(contexto_peticion)
    
    v1 = APIRouter(prefix = '/api/v1')
    for rutas in RUTAS:
        v1.include_router(rutas)
    app.include_router(v1)

    @app.get("/health", tags=["Sistema"], summary="Estado de la API y de la conexión a la base")
    async def health():
        if await conexion_disponible(): 
            return {"mensaje": "API funcionando correctamente", "datos": {"baseDeDatos": "ok"}}
        return JSONResponse(status_code=503, content={
            "codigo": "sin_base_de_datos", "mensaje": "La API no tiene conexión a la base de datos"})

    return app
