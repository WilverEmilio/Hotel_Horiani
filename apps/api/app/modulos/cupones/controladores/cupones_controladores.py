from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.cupones_esquema import (
    ActualizarCuponEsquema,
    CrearCuponEsquema,
    CuponesConsulta,
    VistaPreviaEsquema,
)
from ..servicios import cupones_servicio as servicio


async def crear(datos: CrearCuponEsquema, actor: ActorDep):
    return respuesta("Cupón creado correctamente", await servicio.crear(actor.id_usuario, datos))


async def actualizar(id_cupon: int, datos: ActualizarCuponEsquema, actor: ActorDep):
    return respuesta("Cupón actualizado correctamente", await servicio.actualizar(actor.id_usuario, id_cupon, datos))


async def listar(q: Annotated[CuponesConsulta, Query()], actor: ActorDep):
    return respuesta("Cupones obtenidos correctamente", await servicio.listar(actor.id_usuario, q))


async def obtener(id_cupon: int, actor: ActorDep):
    return respuesta("Cupón obtenido correctamente", await servicio.obtener(actor.id_usuario, id_cupon))


async def vista_previa(datos: VistaPreviaEsquema, actor: ActorDep):
    return respuesta("Descuento calculado correctamente", await servicio.vista_previa(actor.id_usuario, datos))