import logging

import psycopg

from .error_aplicacion import ErrorAplicacion

log = logging.getLogger('horiani.errores')

MENSAJE_INTERNO = "Ocurrió un error interno en el servidor"
MENSAJE_REINTENTAR = "Hubo mucha demanda en este momento. Intente de nuevo"


# Errores de PostgreSQL que no son de negocio pero tienen una respuesta clara
SQLSTATE_HTTP: dict[str, tuple[int, str, str]] = {
    "23505": (409, "registro_duplicado", "El registro ya existe"),
    "23503": (409, "registro_relacionado", "El registro está relacionado con otros datos"),
    "23001": (409, "operacion_no_permitida", "Esta operación no está permitida sobre el registro"),
    "23P01": (409, "conflicto_de_fechas", "Las fechas se cruzan con otro registro"),
    "40P01": (409, "reintentar", MENSAJE_REINTENTAR),   # interbloqueo
    "40001": (409, "reintentar", MENSAJE_REINTENTAR),   # conflicto de serialización
    "22P02": (400, "valor_invalido", "Los datos proporcionados no son válidos"),
    "22007": (400, "fecha_invalida", "Una de las fechas enviadas no es válida"),
    "22008": (400, "fecha_invalida", "Una de las fechas enviadas no es válida"),
    "22003": (400, "valor_fuera_de_rango", "Uno de los valores está fuera del rango permitido"),
    "22001": (400, "texto_muy_largo", "Uno de los textos es demasiado largo"),
}

def traducir_error_bd(e: psycopg.Error) -> ErrorAplicacion:
    estado_sql = e.sqlstate or ""
    diag = e.diag
    mensaje = diag.message_primary or MENSAJE_INTERNO

    if estado_sql.startswith("HH4") and estado_sql[2:].isdigit():
        return ErrorAplicacion(mensaje, diag.message_detail or 'error_negocio', int(estado_sql[2:]))
    
    if estado_sql == '23514':
        return ErrorAplicacion('Uno de los datos no cumple las reglas del sistema', 
    diag.constraint_name or 'dato_invalido', 422)

    if estado_sql in SQLSTATE_HTTP:
        estado, codigo, texto = SQLSTATE_HTTP[estado_sql]
        if estado_sql == "23001" and diag.message_primary:
            texto = diag.message_primary  
        if estado_sql == "23P01" and diag.constraint_name:
            codigo = diag.constraint_name
        return ErrorAplicacion(texto, codigo, estado)

    log.error('Error de base de datos no controlado [%s]: %s | %s', estado_sql, mensaje, diag.message_detail)
    return ErrorAplicacion(MENSAJE_INTERNO, 'Error_interno', 500)
