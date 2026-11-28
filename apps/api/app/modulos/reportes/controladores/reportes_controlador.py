from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.reportes_esquema import (
    CancelacionesConsulta,
    ClientesFrecuentesConsulta,
    DashboardConsulta,
    IngresosConsulta,
    InventarioReporteConsulta,
    PeriodoConsulta,
)
from ..servicios import reportes_servicio as servicio

_OK = "Reporte generado correctamente"


async def dashboard(q: Annotated[DashboardConsulta, Query()], actor: ActorDep):
    return respuesta("Resumen obtenido correctamente", await servicio.resumen_dashboard(actor.id_usuario, q.id_hotel))


async def ingresos(q: Annotated[IngresosConsulta, Query()], actor: ActorDep):
    return respuesta(_OK, await servicio.ingresos(actor.id_usuario, q))


async def ocupacion(q: Annotated[PeriodoConsulta, Query()], actor: ActorDep):
    return respuesta(_OK, await servicio.ocupacion(actor.id_usuario, q))


async def ocupacion_diaria(q: Annotated[PeriodoConsulta, Query()], actor: ActorDep):
    return respuesta(_OK, await servicio.ocupacion_diaria(actor.id_usuario, q))


async def clientes_frecuentes(q: Annotated[ClientesFrecuentesConsulta, Query()], actor: ActorDep):
    return respuesta(_OK, await servicio.clientes_frecuentes(actor.id_usuario, q))


async def cancelaciones(q: Annotated[CancelacionesConsulta, Query()], actor: ActorDep):
    return respuesta(_OK, await servicio.cancelaciones(actor.id_usuario, q))


async def cancelaciones_resumen(q: Annotated[PeriodoConsulta, Query()], actor: ActorDep):
    return respuesta(_OK, await servicio.cancelaciones_resumen(actor.id_usuario, q))


async def cupones(q: Annotated[PeriodoConsulta, Query()], actor: ActorDep):
    return respuesta(_OK, await servicio.cupones(actor.id_usuario, q))


async def inventario(q: Annotated[InventarioReporteConsulta, Query()], actor: ActorDep):
    return respuesta(_OK, await servicio.inventario(actor.id_usuario, q))