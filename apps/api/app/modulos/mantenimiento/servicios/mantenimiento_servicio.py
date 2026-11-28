from ....shared.utilidades.respuesta import paginar
from ..esquemas.mantenimiento_esquema import (
    BloquearEsquema,
    BloqueosConsulta,
    ReportarEsquema,
    ReportesConsulta,
)
from ..repositorios import matenimiento_repositorio as repositorio


async def reportar(id_actor: int, d: ReportarEsquema) -> dict:
    return {
        "id_reporte_mantenimiento": await repositorio.reportar(id_actor, d.id_hotel, d.id_habitacion, d.descripcion)
    }


async def cambiar_estado(id_actor: int, id_reporte: int, estado: str, solucion: str | None) -> dict:
    await repositorio.cambiar_estado(id_actor, id_reporte, estado, solucion)
    return {"id_reporte_mantenimiento": id_reporte, "estado": estado}


async def listar_reportes(id_actor: int, q: ReportesConsulta) -> dict:
    filas = await repositorio.listar_reportes(
        id_actor, q.id_hotel, q.estado, q.id_habitacion, q.pagina, q.registros_por_pagina
    )
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def bloquear_habitacion(id_actor: int, d: BloquearEsquema) -> dict:
    id_bloqueo = await repositorio.bloquear_habitacion(
        id_actor, d.id_habitacion, d.fecha_inicio, d.fecha_fin, d.motivo, d.id_reporte
    )
    return {"id_bloqueo_habitacion": id_bloqueo}


async def liberar_bloqueo(id_actor: int, id_bloqueo: int) -> dict:
    await repositorio.liberar_bloqueo(id_actor, id_bloqueo)
    return {"id_bloqueo_habitacion": id_bloqueo}


async def listar_bloqueos(id_actor: int, q: BloqueosConsulta) -> list[dict]:
    return await repositorio.listar_bloqueos(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta, q.incluir_inactivos)