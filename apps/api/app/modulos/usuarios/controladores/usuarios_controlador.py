from ....shared.esquemas.comunes import CambiarEstadoEsquema
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..servicios import usuarios_servicio as servicio


async def listar_roles(actor: ActorDep):
    return respuesta("Roles obtenidos correctamente", await servicio.listar_roles(actor.id_usuario))


async def cambiar_estado(id_usuario: int, datos: CambiarEstadoEsquema, actor: ActorDep):
    resultado = await servicio.cambiar_estado(actor.id_usuario, id_usuario, datos.activo)
    mensaje = "Usuario activado correctamente" if datos.activo else "Usuario desactivado correctamente"
    return respuesta(mensaje, resultado)


async def generar_enlace_contrasena(id_usuario: int, actor: ActorDep):
    return respuesta("Enlace generado correctamente. Compártalo con el usuario; solo se muestra una vez",
                     await servicio.generar_enlace_contrasena(actor.id_usuario, id_usuario))