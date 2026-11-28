
from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def crear_tarea(id_actor: int, id_habitacion: int, observacion: str | None) -> int:
    return await ejecutar.valor("sp_limpieza_crear_tarea", id_actor, id_habitacion, observacion)


async def asignar_tarea(id_actor: int, id_tarea: int, id_empleado: int) -> None:
    await ejecutar.procedimiento("sp_limpieza_asignar_tarea", id_actor, id_tarea, id_empleado)


async def tomar_tarea(id_actor: int, id_tarea: int) -> None:
    await ejecutar.procedimiento("sp_limpieza_tomar_tarea", id_actor, id_tarea)


async def completar_tarea(id_actor: int, id_tarea: int, observacion: str | None) -> dict:
    return await ejecutar.fila("sp_limpieza_completar_tarea", id_actor, id_tarea, observacion)


async def listar_tareas(
    id_actor: int, id_hotel: int, estado: str | None, solo_mias: bool, pagina: int, tamano: int
) -> list[dict]:
    return await ejecutar.filas("sp_limpieza_listar_tareas", id_actor, id_hotel, estado, solo_mias, pagina, tamano)