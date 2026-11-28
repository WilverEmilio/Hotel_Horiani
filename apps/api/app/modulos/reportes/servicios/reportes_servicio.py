from ....shared.utilidades.respuesta import paginar
from ..esquemas.reportes_esquema import (
    CancelacionesConsulta,
    ClientesFrecuentesConsulta,
    IngresosConsulta,
    InventarioReporteConsulta,
    PeriodoConsulta,
)
from ..repositorios import reportes_repositorio as repositorio


async def resumen_dashboard(id_actor: int, id_hotel: int) -> dict | None:
    return await repositorio.resumen_dashboard(id_actor, id_hotel)


async def ingresos(id_actor: int, q: IngresosConsulta) -> list[dict]:
    return await repositorio.ingresos(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta, q.agrupacion)


async def ocupacion(id_actor: int, q: PeriodoConsulta) -> list[dict]:
    return await repositorio.ocupacion(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta)


async def ocupacion_diaria(id_actor: int, q: PeriodoConsulta) -> list[dict]:
    return await repositorio.ocupacion_diaria(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta)


async def clientes_frecuentes(id_actor: int, q: ClientesFrecuentesConsulta) -> list[dict]:
    return await repositorio.clientes_frecuentes(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta, q.limite)


async def cancelaciones(id_actor: int, q: CancelacionesConsulta) -> dict:
    filas = await repositorio.cancelaciones(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta, q.tipo, q.pagina,
                                            q.registros_por_pagina)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def cancelaciones_resumen(id_actor: int, q: PeriodoConsulta) -> list[dict]:
    return await repositorio.cancelaciones_resumen(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta)


async def cupones(id_actor: int, q: PeriodoConsulta) -> list[dict]:
    return await repositorio.cupones(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta)


async def inventario(id_actor: int, q: InventarioReporteConsulta) -> list[dict]:
    return await repositorio.inventario(id_actor, q.id_hotel, q.fecha_desde, q.fecha_hasta, q.clase)