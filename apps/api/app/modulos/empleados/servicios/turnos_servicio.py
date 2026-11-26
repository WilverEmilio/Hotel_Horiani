from datetime import date

from ..esquemas.turnos_esquema import (
    ActualizarTurnoEsquema,
    AsignarTurnoEsquema,
    CrearTurnoEsquema,
    TurnosConsulta,
)
from ..repositorios import turnos_repositorio as repositorio


async def crear(id_actor: int, d: CrearTurnoEsquema) -> dict:
    return {"id_turno": await repositorio.crear(id_actor, d.id_hotel, d.nombre, d.hora_inicio, d.hora_fin)}


async def actualizar(id_actor: int, id_turno: int, d: ActualizarTurnoEsquema) -> dict:
    await repositorio.actualizar(id_actor, id_turno, d.nombre, d.hora_inicio, d.hora_fin, d.activo)
    return {"id_turno": id_turno}


async def listar(id_actor: int, q: TurnosConsulta) -> list[dict]:
    return await repositorio.listar(id_actor, q.id_hotel, q.incluir_inactivos)


async def asignar(id_actor: int, id_empleado: int, d: AsignarTurnoEsquema) -> dict:
    return {"id_empleado_turno": await repositorio.asignar(id_actor, id_empleado, d.id_turno, d.fecha_desde)}


async def finalizar(id_actor: int, id_empleado_turno: int, fecha_hasta: date) -> dict:
    await repositorio.finalizar(id_actor, id_empleado_turno, fecha_hasta)
    return {"id_empleado_turno": id_empleado_turno, "fecha_hasta": fecha_hasta}