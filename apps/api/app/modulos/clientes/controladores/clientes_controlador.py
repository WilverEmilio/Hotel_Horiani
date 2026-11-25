from typing import Annotated

from fastapi import Query

from ....shared.esquemas.comunes import CambiarEstadoEsquema
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.clientes_esquema import (
    ActualizarClienteEsquema,
    ClientesConsulta,
    CuentaEsquema,
    MiPerfilEsquema,
    RegistrarClienteEsquema,
)
from ..servicios import clientes_servicio as servicio


async def registrar(datos: RegistrarClienteEsquema, actor: ActorDep):
    return respuesta("Cliente registrado correctamente",
                     await servicio.registrar_en_recepcion(actor.id_usuario, datos))


async def listar(q: Annotated[ClientesConsulta, Query()], actor: ActorDep):
    return respuesta("Clientes obtenidos correctamente", await servicio.listar(actor.id_usuario, q))


async def actualizar_mi_perfil(datos: MiPerfilEsquema, actor: ActorDep):
    await servicio.actualizar_mi_perfil(actor.id_usuario, datos)
    return respuesta("Perfil actualizado correctamente")


async def obtener(id_cliente: int, actor: ActorDep):
    return respuesta("Cliente obtenido correctamente", await servicio.obtener(actor.id_usuario, id_cliente))


async def actualizar(id_cliente: int, datos: ActualizarClienteEsquema, actor: ActorDep):
    return respuesta("Cliente actualizado correctamente",
                     await servicio.actualizar(actor.id_usuario, id_cliente, datos))


async def crear_cuenta(id_cliente: int, datos: CuentaEsquema, actor: ActorDep):
    return respuesta("Cuenta creada correctamente. Genere un enlace para que el cliente defina su contraseña",
                     await servicio.crear_cuenta(actor.id_usuario, id_cliente, datos.correo))


async def cambiar_activo(id_cliente: int, datos: CambiarEstadoEsquema, actor: ActorDep):
    return respuesta("Cliente activado correctamente" if datos.activo else "Cliente desactivado correctamente",
                     await servicio.cambiar_activo(actor.id_usuario, id_cliente, datos.activo))