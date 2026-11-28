from datetime import date

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def resumen_dashboard(id_actor: int, id_hotel: int) -> dict | None:
    return await ejecutar.fila("sp_reportes_resumen_dashboard", id_actor, id_hotel)


async def ingresos(id_actor: int, id_hotel: int | None, desde: date, hasta: date, agrupacion: str) -> list[dict]:
    return await ejecutar.filas("sp_reportes_ingresos", id_actor, id_hotel, desde, hasta, agrupacion)


async def ocupacion(id_actor: int, id_hotel: int | None, desde: date, hasta: date) -> list[dict]:
    return await ejecutar.filas("sp_reportes_ocupacion", id_actor, id_hotel, desde, hasta)


async def ocupacion_diaria(id_actor: int, id_hotel: int | None, desde: date, hasta: date) -> list[dict]:
    return await ejecutar.filas("sp_reportes_ocupacion_diaria", id_actor, id_hotel, desde, hasta)


async def clientes_frecuentes(id_actor: int, id_hotel: int | None, desde: date, hasta: date,
                              limite: int) -> list[dict]:
    return await ejecutar.filas("sp_reportes_clientes_frecuentes", id_actor, id_hotel, desde, hasta, limite)


async def cancelaciones(id_actor: int, id_hotel: int | None, desde: date, hasta: date, tipo: str | None,
                        pagina: int, tamano: int) -> list[dict]:
    return await ejecutar.filas("sp_reportes_cancelaciones", id_actor, id_hotel, desde, hasta, tipo, pagina, tamano)


async def cancelaciones_resumen(id_actor: int, id_hotel: int | None, desde: date, hasta: date) -> list[dict]:
    return await ejecutar.filas("sp_reportes_cancelaciones_resumen", id_actor, id_hotel, desde, hasta)


async def cupones(id_actor: int, id_hotel: int | None, desde: date, hasta: date) -> list[dict]:
    return await ejecutar.filas("sp_reportes_cupones", id_actor, id_hotel, desde, hasta)


async def inventario(id_actor: int, id_hotel: int, desde: date, hasta: date, clase: str | None) -> list[dict]:
    return await ejecutar.filas("sp_reportes_inventario", id_actor, id_hotel, desde, hasta, clase)