from typing import Annotated

from fastapi import Query

from ....shared.esquemas.comunes import CambiarEstadoEsquema
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.habitaciones_esquema import (
    ActualizarHabitacionEsquema,
    CrearHabitacionEsquema,
    EstadoHabitacionEsquema,
    HabitacionesConsulta,
)
from ..servicios import habitaciones_servicio as servicio


async def listar(q: Annotated[HabitacionesConsulta, Query()], actor: ActorDep):
    return respuesta("Habitaciones obtenidas correctamente", await servicio.listar(actor.id_usuario, q))


async def crear(datos: CrearHabitacionEsquema, actor: ActorDep):
    return respuesta("Habitación creada correctamente", await servicio.crear(actor.id_usuario, datos))


async def actualizar(id_habitacion: int, datos: ActualizarHabitacionEsquema, actor: ActorDep):
    return respuesta("Habitación actualizada correctamente",
                     await servicio.actualizar(actor.id_usuario, id_habitacion, datos))


async def cambiar_estado(id_habitacion: int, datos: EstadoHabitacionEsquema, actor: ActorDep):
    return respuesta("Estado de la habitación actualizado correctamente",
                     await servicio.cambiar_estado(actor.id_usuario, id_habitacion, datos.estado))


async def cambiar_activo(id_habitacion: int, datos: CambiarEstadoEsquema, actor: ActorDep):
    mensaje = "Habitación activada correctamente" if datos.activo else "Habitación desactivada correctamente"
    return respuesta(mensaje, await servicio.cambiar_activo(actor.id_usuario, id_habitacion, datos.activo))