from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.turnos_esquema import (
    ActualizarTurnoEsquema,
    AsignarTurnoEsquema,
    CrearTurnoEsquema,
    FinalizarTurnoEsquema,
    TurnosConsulta,
)
from ..servicios import turnos_servicio as servicio


async def listar(q: Annotated[TurnosConsulta, Query()], actor: ActorDep):
    return respuesta("Turnos obtenidos correctamente", await servicio.listar(actor.id_usuario, q))


async def crear(datos: CrearTurnoEsquema, actor: ActorDep):
    return respuesta("Turno creado correctamente", await servicio.crear(actor.id_usuario, datos))


async def actualizar(id_turno: int, datos: ActualizarTurnoEsquema, actor: ActorDep):
    return respuesta("Turno actualizado correctamente", await servicio.actualizar(actor.id_usuario, id_turno, datos))


async def asignar(id_empleado: int, datos: AsignarTurnoEsquema, actor: ActorDep):
    return respuesta("Turno asignado correctamente", await servicio.asignar(actor.id_usuario, id_empleado, datos))


async def finalizar(id_empleado_turno: int, datos: FinalizarTurnoEsquema, actor: ActorDep):
    return respuesta("Asignación de turno finalizada",
                     await servicio.finalizar(actor.id_usuario, id_empleado_turno, datos.fecha_hasta))