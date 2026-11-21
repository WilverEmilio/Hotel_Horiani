from fastapi import Request

from ..base_de_datos.ejecutar_procedimiento import ip_actual


async def contexto_peticion(request: Request, call_next):
    token = ip_actual.set(request.client.host if request.client else None)
    try:
        respuesta = await call_next(request)
    finally:
        ip_actual.reset(token)
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    return respuesta