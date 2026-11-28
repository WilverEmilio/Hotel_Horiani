from ....shared.utilidades.respuesta import paginar
from ..esquemas.limpieza_esquema import CrearTareaEsquema, TareasConsulta
from ..repositorios import limpieza_repositorio as repositorio


async def crear_tarea(id_actor: int, d: CrearTareaEsquema) -> dict:
    return {"id_tarea_limpieza": await repositorio.crear_tarea(id_actor, d.id_habitacion, d.observacion)}


async def asignar_tarea(id_actor: int, id_tarea: int, id_empleado: int) -> dict:
    await repositorio.asignar_tarea(id_actor, id_tarea, id_empleado)
    return {"id_tarea_limpieza": id_tarea, "id_empleado": id_empleado}


async def tomar_tarea(id_actor: int, id_tarea: int) -> dict:
    await repositorio.tomar_tarea(id_actor, id_tarea)
    return {"id_tarea_limpieza": id_tarea}


async def completar_tarea(id_actor: int, id_tarea: int, observacion: str | None) -> dict:
    return await repositorio.completar_tarea(id_actor, id_tarea, observacion)


async def listar_tareas(id_actor: int, q: TareasConsulta) -> dict:
    filas = await repositorio.listar_tareas(
        id_actor, q.id_hotel, q.estado, q.solo_mias, q.pagina, q.registros_por_pagina
    )
    return paginar(filas, q.pagina, q.registros_por_pagina)