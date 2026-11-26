from ....shared.utilidades.respuesta import paginar
from ..esquemas.asistencia_esquema import (
    AsistenciaConsulta,
    HojaDelDiaConsulta,
    RegistrarRangoEsquema,
    RegistrearAsistenciaEsquema,
    ResumenAsistenciaConsulta,
)
from ..repositorios import asistencia_repositorio as repositorio


async def registrar(id_actor: int, d: RegistrearAsistenciaEsquema) -> dict:
    id_asistencia = await repositorio.registrar(id_actor, d.id_empleado, d.id_hotel, d.fecha, d.id_turno, d.estado,
                                                d.observacion)
    return {"id_asistencia": id_asistencia}


async def registrar_rango(id_actor: int, d: RegistrarRangoEsquema) -> dict:
    dias = await repositorio.registrar_rango(id_actor, d.id_empleado, d.id_hotel, d.fecha_desde, d.fecha_hasta,
                                             d.estado, d.observacion)
    return {"dias_registrados": dias}


async def hoja_del_dia(id_actor: int, q: HojaDelDiaConsulta) -> list[dict]:
    return await repositorio.hoja_del_dia(id_actor, q.id_hotel, q.fecha)


async def listar(id_actor: int, q: AsistenciaConsulta) -> dict:
    filas = await repositorio.listar(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta, q.id_empleado, q.estado,
                                     q.pagina, q.registros_por_pagina)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def resumen(id_actor: int, q: ResumenAsistenciaConsulta) -> list[dict]:
    return await repositorio.resumen(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta)