from datetime import date

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def reportar(id_actor: int, id_hotel: int, id_habitacion: int | None, descripcion: str) -> int:
    return await ejecutar.valor("sp_mantenimiento_reportar", id_actor, id_hotel, id_habitacion, descripcion)


async def cambiar_estado(id_actor: int, id_reporte: int, estado: str, solucion: str | None) -> None:
    await ejecutar.procedimiento("sp_mantenimiento_cambiar_estado", id_actor, id_reporte, estado, solucion)


async def listar_reportes(
    id_actor: int, id_hotel: int, estado: str | None, id_habitacion: int | None, pagina: int, tamano: int
) -> list[dict]:
    return await ejecutar.filas(
        "sp_mantenimiento_listar_reportes", id_actor, id_hotel, estado, id_habitacion, pagina, tamano
    )


async def bloquear_habitacion(
    id_actor: int, id_habitacion: int, inicio: date, fin: date, motivo: str, id_reporte: int | None
) -> int:
    return await ejecutar.valor(
        "sp_mantenimiento_bloquear_habitacion", id_actor, id_habitacion, inicio, fin, motivo, id_reporte
    )


async def liberar_bloqueo(id_actor: int, id_bloqueo: int) -> None:
    await ejecutar.procedimiento("sp_mantenimiento_liberar_bloqueo", id_actor, id_bloqueo)


async def listar_bloqueos(
    id_actor: int, id_hotel: int, desde: date, hasta: date, incluir_inactivos: bool
) -> list[dict]:
    return await ejecutar.filas(
        "sp_mantenimiento_listar_bloqueos", id_actor, id_hotel, desde, hasta, incluir_inactivos
    )


async def sincronizar_estados() -> int:
    return await ejecutar.valor("sp_mantenimiento_sincronizar_estados")