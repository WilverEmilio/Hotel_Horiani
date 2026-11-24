from uuid import UUID

from ....shared.errores.error_aplicacion import ErrorAplicacion
from ....shared.esquemas.comunes import ConsultaPaginada
from ....shared.utilidades.mapeo import a_snake
from ....shared.utilidades.respuesta import paginar
from ..esquemas.reservaciones_esquema import (
    CrearReservacionEsquema,
    DisponibilidadConsulta,
    FechasConsulta,
    ReservacionesConsulta,
    habitaciones_para_bd,
)
from ..repositorio import reservaciones_repositorio as repositorio


async def consultar_disponibilidad(id_hotel: int, q: DisponibilidadConsulta) -> list[dict]:
    return await repositorio.consultar_disponibilidad(id_hotel, q.fecha_entrada, q.fecha_salida, q.huespedes)


async def listar_habitaciones_libres(id_hotel: int, id_tipo: int, q: FechasConsulta) -> list[dict]:
    return await repositorio.listar_habitaciones_libres(id_hotel, id_tipo, q.fecha_entrada, q.fecha_salida)


async def crear(id_actor: int, d: CrearReservacionEsquema, origen: str, llave: UUID) -> dict:
    return await repositorio.crear(id_actor, d.id_hotel, d.fecha_entrada, d.fecha_salida,
                                   habitaciones_para_bd(d.habitaciones), d.codigo_cupon, origen, llave, d.id_cliente)


async def obtener(id_actor: int, id_reservacion: int) -> dict:
    fila = await repositorio.obtener(id_actor, id_reservacion)
    if not fila:
        raise ErrorAplicacion("La reservación no existe", "reservacion_no_encontrada", 404)
    return fila


async def listar_mias(id_actor: int, q: ConsultaPaginada) -> dict:
    filas = await repositorio.listar_mias(id_actor, q.pagina, q.registros_por_pagina)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def listar(id_actor: int, q: ReservacionesConsulta) -> dict:
    filas = await repositorio.listar(id_actor, q.id_hotel, q.estado, q.id_cliente, q.fecha_desde, q.fecha_hasta,
                                     q.busqueda, q.pagina, q.registros_por_pagina, a_snake(q.ordenar_por),
                                     q.direccion)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def cancelar(id_actor: int, id_reservacion: int, motivo: str) -> dict:
    return await repositorio.cancelar(id_actor, id_reservacion, motivo)


async def reasignar_habitacion(id_actor: int, id_reservacion_habitacion: int, id_habitacion_nueva: int,
                               motivo: str) -> dict:
    await repositorio.reasignar_habitacion(id_actor, id_reservacion_habitacion, id_habitacion_nueva, motivo)
    return {"id_reservacion_habitacion": id_reservacion_habitacion, "id_habitacion": id_habitacion_nueva}