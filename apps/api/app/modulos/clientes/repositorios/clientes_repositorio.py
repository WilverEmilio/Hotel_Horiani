from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def registrar_en_recepcion(id_actor: int, nombres: str, apellidos: str, telefono: str, tipo_documento: str,
                                 numero_documento: str, pais: str, correo: str | None) -> dict:
    return await ejecutar.fila("sp_clientes_registrar_en_recepcion", id_actor, nombres, apellidos, telefono,
                               tipo_documento, numero_documento, pais, correo)


async def crear_cuenta(id_actor: int, id_cliente: int, correo: str) -> int:
    return await ejecutar.valor("sp_clientes_crear_cuenta", id_actor, id_cliente, correo)


async def actualizar(id_actor: int, id_cliente: int, nombres: str, apellidos: str, telefono: str,
                     tipo_documento: str, numero_documento: str, pais: str) -> None:
    await ejecutar.procedimiento("sp_clientes_actualizar", id_actor, id_cliente, nombres, apellidos, telefono,
                                 tipo_documento, numero_documento, pais)


async def actualizar_mi_perfil(id_actor: int, nombres: str, apellidos: str, telefono: str, pais: str) -> None:
    await ejecutar.procedimiento("sp_clientes_actualizar_mi_perfil", id_actor, nombres, apellidos, telefono, pais)


async def cambiar_activo(id_actor: int, id_cliente: int, activo: bool) -> None:
    await ejecutar.procedimiento("sp_clientes_cambiar_activo", id_actor, id_cliente, activo)


async def obtener(id_actor: int, id_cliente: int) -> dict | None:
    return await ejecutar.fila("sp_clientes_obtener", id_actor, id_cliente)


async def listar(id_actor: int, busqueda: str | None, activo: bool | None, pagina: int, tamano: int, orden: str,
                 direccion: str) -> list[dict]:
    return await ejecutar.filas("sp_clientes_listar", id_actor, busqueda, activo, pagina, tamano, orden, direccion)