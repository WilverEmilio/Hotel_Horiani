"""Manejo de errores: todas las respuestas de error son {"codigo", "mensaje", "detalles"?}."""
import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from ..errores.error_aplicacion import ErrorAplicacion

log = logging.getLogger("horiani.errores")

MENSAJE_INTERNO = "Ocurrió un error interno en el servidor"

MENSAJES_VALIDACION = {
    "missing": "Campo obligatorio",
    "string_type": "Debe ser texto",
    "string_too_short": "Texto demasiado corto",
    "string_too_long": "Texto demasiado largo",
    "string_pattern_mismatch": "Formato no válido",
    "int_parsing": "Debe ser un número entero",
    "int_type": "Debe ser un número entero",
    "float_parsing": "Debe ser un número",
    "decimal_parsing": "Debe ser un número",
    "decimal_max_places": "Máximo 2 decimales",
    "greater_than": "Valor demasiado bajo",
    "greater_than_equal": "Valor demasiado bajo",
    "less_than": "Valor demasiado alto",
    "less_than_equal": "Valor demasiado alto",
    "literal_error": "Valor no permitido",
    "date_parsing": "Fecha no válida (use AAAA-MM-DD)",
    "date_from_datetime_parsing": "Fecha no válida (use AAAA-MM-DD)",
    "time_parsing": "Hora no válida (use HH:MM)",
    "uuid_parsing": "Debe ser un UUID",
    "bool_parsing": "Debe ser verdadero o falso",
    "json_invalid": "El cuerpo de la solicitud no es un JSON válido",
    "list_type": "Debe ser una lista",
    "too_short": "La lista está vacía o tiene muy pocos elementos",
    "too_long": "La lista tiene demasiados elementos",
    "extra_forbidden": "Campo no permitido",
}


def _cuerpo(codigo: str, mensaje: str, detalles: list | None = None) -> dict:
    cuerpo = {"codigo": codigo, "mensaje": mensaje}
    if detalles:
        cuerpo["detalles"] = detalles
    return cuerpo


def _mensaje_validacion(err: dict) -> str:
    if err["type"] == "value_error": 
        return str(err.get("ctx", {}).get("error", err["msg"]))
    return MENSAJES_VALIDACION.get(err["type"], err["msg"])


def registrar_manejo_errores(app: FastAPI) -> None:
    @app.exception_handler(ErrorAplicacion)
    async def _error_aplicacion(_: Request, e: ErrorAplicacion):
        mensaje = MENSAJE_INTERNO if e.estado_http >= 500 else e.mensaje
        return JSONResponse(status_code=e.estado_http, content=_cuerpo(e.codigo, mensaje, e.detalles),
                            headers=e.encabezados)

    @app.exception_handler(RequestValidationError)
    async def _validacion(_: Request, e: RequestValidationError):
        detalles = [
            {"campo": ".".join(str(p) for p in err["loc"]), "mensaje": _mensaje_validacion(err)}
            for err in e.errors()
        ]
        return JSONResponse(status_code=400,
                            content=_cuerpo("datos_invalidos", "Los datos enviados no son válidos", detalles))

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, e: StarletteHTTPException):
        if e.status_code == 404:
            return JSONResponse(status_code=404, content=_cuerpo("no_encontrado", "Recurso no encontrado"))
        if e.status_code == 405:
            return JSONResponse(status_code=405, content=_cuerpo("metodo_no_permitido", "Método no permitido"))
        mensaje = e.detail if isinstance(e.detail, str) else "Error"
        return JSONResponse(status_code=e.status_code, content=_cuerpo("error", mensaje),
                            headers=getattr(e, "headers", None))

    @app.exception_handler(Exception)
    async def _inesperado(_: Request, e: Exception):
        log.exception("Error no controlado") 
        return JSONResponse(status_code=500, content=_cuerpo("error_interno", MENSAJE_INTERNO))