from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.mantenimiento_esquema import (
    BloquearEsquema,
    BloqueosConsulta,
    EstadoReporteEsquema,
    ReportarEsquema,
    ReportesConsulta,
)
from ..servicios import mantenimiento_servicio as servicio


async def reportar(datos: ReportarEsquema, actor: ActorDep):
    return respuesta("Reporte registrado correctamente", await servicio.reportar(actor.id_usuario, datos))


async def listar_reportes(q: Annotated[ReportesConsulta, Query()], actor: ActorDep):
    return respuesta("Reportes obtenidos correctamente", await servicio.listar_reportes(actor.id_usuario, q))


async def cambiar_estado(id_reporte: int, datos: EstadoReporteEsquema, actor: ActorDep):
    return respuesta(
        "Reporte actualizado correctamente",
        await servicio.cambiar_estado(actor.id_usuario, id_reporte, datos.estado, datos.solucion),
    )


async def bloquear_habitacion(datos: BloquearEsquema, actor: ActorDep):
    return respuesta(
        "Habitación bloqueada correctamente", await servicio.bloquear_habitacion(actor.id_usuario, datos)
    )


async def liberar_bloqueo(id_bloqueo: int, actor: ActorDep):
    return respuesta("Bloqueo liberado correctamente", await servicio.liberar_bloqueo(actor.id_usuario, id_bloqueo))


async def listar_bloqueos(q: Annotated[BloqueosConsulta, Query()], actor: ActorDep):
    return respuesta("Bloqueos obtenidos correctamente", await servicio.listar_bloqueos(actor.id_usuario, q))