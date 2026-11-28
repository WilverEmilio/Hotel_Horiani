from datetime import date

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def recibir_lote(id_actor: int, id_hotel: int, items: list[dict], observacion: str | None) -> int:
    return await ejecutar.valor("sp_lavanderia_recibir_lote", id_actor, id_hotel, ejecutar.json(items), observacion)


async def devolver_lote(id_actor: int, id_lote: int, items: list[dict], observacion: str | None) -> list[dict]:
    return await ejecutar.filas("sp_lavanderia_devolver_lote", id_actor, id_lote, ejecutar.json(items), observacion)


async def listar_lotes(id_actor: int, id_hotel: int, estado: str | None, desde: date | None, hasta: date | None,
                       pagina: int, tamano: int) -> list[dict]:
    return await ejecutar.filas("sp_lavanderia_listar_lotes", id_actor, id_hotel, estado, desde, hasta, pagina, tamano)


async def obtener_lote(id_actor: int, id_lote: int) -> dict | None:
    return await ejecutar.fila("sp_lavanderia_obtener_lote", id_actor, id_lote)