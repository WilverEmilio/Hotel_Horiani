from typing import Annotated

from fastapi import Query

from ....shared.esquemas.comunes import ObservacionEsquema
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.limpieza_esquema import (
    AsignarTareaEsquema,
    CrearTareaEsquema,
    TareasConsulta,
)
from ..servicios import limpieza_servicio as servicio


async def crear_tarea(datos: CrearTareaEsquema, actor: ActorDep):
    return respuesta("Tarea de limpieza creada correctamente", await servicio.crear_tarea(actor.id_usuario, datos))


async def listar_tareas(q: Annotated[TareasConsulta, Query()], actor: ActorDep):
    return respuesta("Tareas obtenidas correctamente", await servicio.listar_tareas(actor.id_usuario, q))


async def asignar_tarea(id_tarea: int, datos: AsignarTareaEsquema, actor: ActorDep):
    return respuesta(
        "Tarea asignada correctamente", await servicio.asignar_tarea(actor.id_usuario, id_tarea, datos.id_empleado)
    )


async def tomar_tarea(id_tarea: int, actor: ActorDep):
    return respuesta("Tarea tomada correctamente", await servicio.tomar_tarea(actor.id_usuario, id_tarea))


async def completar_tarea(id_tarea: int, datos: ObservacionEsquema, actor: ActorDep):
    return respuesta(
        "Tarea completada correctamente",
        await servicio.completar_tarea(actor.id_usuario, id_tarea, datos.observacion),
    )