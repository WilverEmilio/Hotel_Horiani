from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.lavanderia_esquema import (
    DevolverLoteEsquema,
    LotesConsulta,
    RecibirLoteEsquema,
)
from ..servicios import lavanderia_servicio as servicio


async def recibir_lote(datos: RecibirLoteEsquema, actor: ActorDep):
    return respuesta("Lote recibido correctamente", await servicio.recibir_lote(actor.id_usuario, datos))


async def devolver_lote(id_lote: int, datos: DevolverLoteEsquema, actor: ActorDep):
    return respuesta("Lote devuelto correctamente", await servicio.devolver_lote(actor.id_usuario, id_lote, datos))


async def listar_lotes(q: Annotated[LotesConsulta, Query()], actor: ActorDep):
    return respuesta("Lotes obtenidos correctamente", await servicio.listar_lotes(actor.id_usuario, q))


async def obtener_lote(id_lote: int, actor: ActorDep):
    return respuesta("Lote obtenido correctamente", await servicio.obtener_lote(actor.id_usuario, id_lote))