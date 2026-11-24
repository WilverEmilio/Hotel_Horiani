from ....shared.esquemas.comunes import ObservacionEsquema
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..servicio import estancia_servicio as servicio


async def hacer_checkin(id_reservacion: int, actor: ActorDep):
    return respuesta("Check-in realizado correctamente", await servicio.hacer_checkin(actor.id_usuario, id_reservacion))


async def hacer_checkout(id_reservacion: int, actor: ActorDep):
    return respuesta("Check-out realizado correctamente",
                     await servicio.hacer_checkout(actor.id_usuario, id_reservacion))


async def marcar_no_presentado(id_reservacion: int, datos: ObservacionEsquema, actor: ActorDep):
    return respuesta("Reservación marcada como no presentada",
                     await servicio.marcar_no_presentado(actor.id_usuario, id_reservacion, datos.observacion))