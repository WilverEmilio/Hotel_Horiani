from ....shared.utilidades.mapeo import a_snake
from ....shared.utilidades.respuesta import paginar
from ..esquemas.habitaciones_esquema import (
    ActualizarHabitacionEsquema,
    CrearHabitacionEsquema,
    HabitacionesConsulta,
)
from ..repositorio import habitaciones_repositorio as repositorio


async def crear(id_actor: int, d: CrearHabitacionEsquema) -> dict:
    return {"id_habitacion": await repositorio.crear(id_actor, d.id_hotel, d.id_tipo_habitacion, d.numero, d.piso)}


async def actualizar(id_actor: int, id_habitacion: int, d: ActualizarHabitacionEsquema) -> dict:
    await repositorio.actualizar(id_actor, id_habitacion, d.id_tipo_habitacion, d.numero, d.piso)
    return {"id_habitacion": id_habitacion}


async def cambiar_estado(id_actor: int, id_habitacion: int, estado: str) -> dict:
    await repositorio.cambiar_estado(id_actor, id_habitacion, estado)
    return {"id_habitacion": id_habitacion, "estado": estado}


async def cambiar_activo(id_actor: int, id_habitacion: int, activo: bool) -> dict:
    await repositorio.cambiar_activo(id_actor, id_habitacion, activo)
    return {"id_habitacion": id_habitacion, "activo": activo}


async def listar(id_actor: int, q: HabitacionesConsulta) -> dict:
    filas = await repositorio.listar(id_actor, q.id_hotel, q.estado, q.id_tipo_habitacion, q.busqueda,
                                     q.incluir_inactivas, q.pagina, q.registros_por_pagina,
                                     a_snake(q.ordenar_por), q.direccion)
    return paginar(filas, q.pagina, q.registros_por_pagina)