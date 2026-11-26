from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.asistencia_esquema import (
    AsistenciaConsulta,
    HojaDelDiaConsulta,
    RegistrarRangoEsquema,
    RegistrearAsistenciaEsquema,
    ResumenAsistenciaConsulta,
)
from ..servicios import asistencia_servicio as servicio


async def registrar(datos: RegistrearAsistenciaEsquema, actor: ActorDep):
    return respuesta("Asistencia registrada correctamente", await servicio.registrar(actor.id_usuario, datos))


async def registrar_rango(datos: RegistrarRangoEsquema, actor: ActorDep):
    return respuesta("Asistencia registrada correctamente", await servicio.registrar_rango(actor.id_usuario, datos))


async def hoja_del_dia(q: Annotated[HojaDelDiaConsulta, Query()], actor: ActorDep):
    return respuesta("Hoja del día obtenida correctamente", await servicio.hoja_del_dia(actor.id_usuario, q))


async def listar(q: Annotated[AsistenciaConsulta, Query()], actor: ActorDep):
    return respuesta("Asistencia obtenida correctamente", await servicio.listar(actor.id_usuario, q))


async def resumen(q: Annotated[ResumenAsistenciaConsulta, Query()], actor: ActorDep):
    return respuesta("Resumen de asistencia obtenido correctamente", await servicio.resumen(actor.id_usuario, q))