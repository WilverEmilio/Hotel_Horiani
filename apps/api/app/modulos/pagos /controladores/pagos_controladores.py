from typing import Annotated

from fastapi import Query, Request

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.encabezado import LlaveDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.pagos_esquema import PagoEnHotelEsquema, PagosConsulta, ReembolsoEsquema
from ..servicios import pagos_servicio as servicio


async def iniciar_anticipo(id_reservacion: int, actor: ActorDep, llave: LlaveDep):
    return respuesta("Pago iniciado. Continúe en la pasarela",
                     await servicio.iniciar_anticipo(actor.id_usuario, id_reservacion, llave))


async def recibir_aviso(pasarela: str, request: Request):
    """Lo llama la pasarela (webhook). Se lee el cuerpo crudo porque la firma se calcula sobre los bytes exactos."""
    encabezados = {k.lower(): v for k, v in request.headers.items()}
    return respuesta("Aviso procesado", await servicio.procesar_aviso(pasarela, await request.body(), encabezados))


async def registrar_en_hotel(id_reservacion: int, datos: PagoEnHotelEsquema, actor: ActorDep, llave: LlaveDep):
    fila = await servicio.registrar_en_hotel(actor.id_usuario, id_reservacion, datos, llave)
    return respuesta("El pago ya había sido registrado" if fila["ya_existia"] else "Pago registrado correctamente", fila)


async def reembolsar(id_pago: int, datos: ReembolsoEsquema, actor: ActorDep, llave: LlaveDep):
    fila = await servicio.reembolsar(actor.id_usuario, id_pago, datos, llave)
    mensaje = "El reembolso ya había sido registrado" if fila["ya_existia"] else "Reembolso registrado correctamente"
    return respuesta(mensaje, fila)


async def listar_por_reservacion(id_reservacion: int, actor: ActorDep):
    return respuesta("Pagos obtenidos correctamente",
                     await servicio.listar_por_reservacion(actor.id_usuario, id_reservacion))


async def listar(q: Annotated[PagosConsulta, Query()], actor: ActorDep):
    return respuesta("Pagos obtenidos correctamente", await servicio.listar(actor.id_usuario, q))