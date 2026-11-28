from ....shared.errores.error_aplicacion import ErrorAplicacion
from ....shared.utilidades.respuesta import paginar
from ..esquemas.lavanderia_esquema import (
    DevolverLoteEsquema,
    LotesConsulta,
    RecibirLoteEsquema,
)
from ..repositorio import lavanderia_repositorio as repositorio


async def recibir_lote(id_actor: int, d: RecibirLoteEsquema) -> dict:
    items = [i.model_dump(mode="json") for i in d.items]
    return {"id_lote_lavanderia": await repositorio.recibir_lote(id_actor, d.id_hotel, items, d.observacion)}


async def devolver_lote(id_actor: int, id_lote: int, d: DevolverLoteEsquema) -> list[dict]:
    items = [i.model_dump(mode="json") for i in d.items]
    return await repositorio.devolver_lote(id_actor, id_lote, items, d.observacion)


async def listar_lotes(id_actor: int, q: LotesConsulta) -> dict:
    filas = await repositorio.listar_lotes(id_actor, q.id_hotel, q.estado, q.fecha_desde, q.fecha_hasta, q.pagina,
                                           q.registros_por_pagina)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def obtener_lote(id_actor: int, id_lote: int) -> dict:
    fila = await repositorio.obtener_lote(id_actor, id_lote)
    if not fila:
        raise ErrorAplicacion("El lote no existe", "lote_no_encontrado", 404)
    return fila