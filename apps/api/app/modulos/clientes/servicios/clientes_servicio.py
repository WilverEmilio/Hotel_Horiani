from ....shared.errores.error_aplicacion import ErrorAplicacion
from ....shared.utilidades.mapeo import a_snake
from ....shared.utilidades.respuesta import paginar
from ..esquemas.clientes_esquema import (
    ActualizarClienteEsquema,
    ClientesConsulta,
    MiPerfilEsquema,
    RegistrarClienteEsquema,
)
from ..repositorios import clientes_repositorio as repositorio


async def registrar_en_recepcion(id_actor: int, d: RegistrarClienteEsquema) -> dict:
    return await repositorio.registrar_en_recepcion(id_actor, d.nombres, d.apellidos, d.telefono, d.tipo_documento,
                                                    d.numero_documento, d.pais, d.correo)


async def crear_cuenta(id_actor: int, id_cliente: int, correo: str) -> dict:
    return {"id_cliente": id_cliente, "id_usuario": await repositorio.crear_cuenta(id_actor, id_cliente, correo)}


async def actualizar(id_actor: int, id_cliente: int, d: ActualizarClienteEsquema) -> dict:
    await repositorio.actualizar(id_actor, id_cliente, d.nombres, d.apellidos, d.telefono, d.tipo_documento,
                                 d.numero_documento, d.pais)
    return {"id_cliente": id_cliente}


async def actualizar_mi_perfil(id_actor: int, d: MiPerfilEsquema) -> None:
    await repositorio.actualizar_mi_perfil(id_actor, d.nombres, d.apellidos, d.telefono, d.pais)


async def cambiar_activo(id_actor: int, id_cliente: int, activo: bool) -> dict:
    await repositorio.cambiar_activo(id_actor, id_cliente, activo)
    return {"id_cliente": id_cliente, "activo": activo}


async def obtener(id_actor: int, id_cliente: int) -> dict:
    fila = await repositorio.obtener(id_actor, id_cliente)
    if not fila:
        raise ErrorAplicacion("El cliente no existe", "cliente_no_encontrado", 404)
    return fila


async def listar(id_actor: int, q: ClientesConsulta) -> dict:
    filas = await repositorio.listar(id_actor, q.busqueda, q.activo, q.pagina, q.registros_por_pagina,
                                     a_snake(q.ordenar_por), q.direccion)
    return paginar(filas, q.pagina, q.registros_por_pagina)