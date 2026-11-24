from typing import Annotated

from fastapi import Query

from ....shared.esquemas.comunes import ConsultaPaginada, MotivoEsquema
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.encabezado import ClienteDep, LlaveDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.reservaciones_esquema import (
    CrearReservacionEsquema,
    DisponibilidadConsulta,
    FechasConsulta,
    ReasignarHabitacionEsquema,
    ReservacionesConsulta,
)
from ..servicio import reservaciones_servicio as servicio


async def consultar_disponibilidad(id_hotel: int, q: Annotated[DisponibilidadConsulta, Query()]):
    return respuesta("Disponibilidad obtenida correctamente", await servicio.consultar_disponibilidad(id_hotel, q))


async def listar_habitaciones_libres(id_hotel: int, id_tipo_habitacion: int, q: Annotated[FechasConsulta, Query()]):
    return respuesta("Habitaciones libres obtenidas correctamente",
                     await servicio.listar_habitaciones_libres(id_hotel, id_tipo_habitacion, q))


async def crear(datos: CrearReservacionEsquema, actor: ActorDep, llave: LlaveDep, cliente: ClienteDep):
    fila = await servicio.crear(actor.id_usuario, datos, cliente, llave)
    mensaje = "La reservación ya había sido creada" if fila["ya_existia"] else "Reservación creada correctamente"
    return respuesta(mensaje, fila)


async def listar_mias(q: Annotated[ConsultaPaginada, Query()], actor: ActorDep):
    return respuesta("Reservaciones obtenidas correctamente", await servicio.listar_mias(actor.id_usuario, q))


async def listar(q: Annotated[ReservacionesConsulta, Query()], actor: ActorDep):
    return respuesta("Reservaciones obtenidas correctamente", await servicio.listar(actor.id_usuario, q))


async def obtener(id_reservacion: int, actor: ActorDep):
    return respuesta("Reservación obtenida correctamente", await servicio.obtener(actor.id_usuario, id_reservacion))


async def cancelar(id_reservacion: int, datos: MotivoEsquema, actor: ActorDep):
    return respuesta("Reservación cancelada correctamente",
                     await servicio.cancelar(actor.id_usuario, id_reservacion, datos.motivo))


async def reasignar_habitacion(id_reservacion_habitacion: int, datos: ReasignarHabitacionEsquema, actor: ActorDep):
    return respuesta("Habitación reasignada correctamente",
                     await servicio.reasignar_habitacion(actor.id_usuario, id_reservacion_habitacion,
                                                         datos.id_habitacion_nueva, datos.motivo))