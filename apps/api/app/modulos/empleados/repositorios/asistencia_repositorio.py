from datetime import date

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def registrar(
    id_actor: int, 
    id_empleado: int, 
    id_hotel: int, 
    fecha: date, 
    id_turno: int | None, 
    estado: str,
    observacion: str | None
) -> int:
    return await ejecutar.valor(
        "sp_asistencia_registrar", 
        id_actor, 
        id_empleado, 
        id_hotel, 
        fecha, 
        id_turno, 
        estado,
        observacion
    )


async def registrar_rango(
    id_actor: int, 
    id_empleado: int, 
    id_hotel: int, 
    fecha_desde: date, 
    fecha_hasta: date,
    estado: str, 
    observacion: str | None
) -> int:
    return await ejecutar.valor(
        "sp_asistencia_registrar_rango", 
        id_actor, 
        id_empleado, 
        id_hotel, 
        fecha_desde,
        fecha_hasta, 
        estado, 
        observacion
    )


async def hoja_del_dia(
    id_actor: int, 
    id_hotel: int, 
    fecha: date
) -> list[dict]:
    return await ejecutar.filas(
        "sp_asistencia_hoja_del_dia", 
        id_actor, 
        id_hotel, 
        fecha
    )


async def listar(
    id_actor: int, 
    id_hotel: int, 
    fecha_desde: date, 
    fecha_hasta: date, 
    id_empleado: int | None,
    estado: str | None, 
    pagina: int, 
    tamano: int
) -> list[dict]:
    return await ejecutar.filas(
        "sp_asistencia_listar", 
        id_actor, 
        id_hotel, 
        fecha_desde, 
        fecha_hasta, 
        id_empleado,
        estado, 
        pagina, 
        tamano
    )


async def resumen(
    id_actor: int, 
    id_hotel: int, 
    fecha_desde: date, 
    fecha_hasta: date
) -> list[dict]:
    return await ejecutar.filas(
        "sp_asistencia_resumen", 
        id_actor, 
        id_hotel, 
        fecha_desde, 
        fecha_hasta
    )