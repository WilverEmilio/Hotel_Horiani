from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def crear(id_actor: int, id_hotel: int, id_tipo: int, numero: str, piso: int | None) -> int:
    return await ejecutar.valor("sp_habitaciones_crear", id_actor, id_hotel, id_tipo, numero, piso)


async def actualizar(id_actor: int, id_habitacion: int, id_tipo: int, numero: str, piso: int | None) -> None:
    await ejecutar.procedimiento("sp_habitaciones_actualizar", id_actor, id_habitacion, id_tipo, numero, piso)


async def cambiar_estado(id_actor: int, id_habitacion: int, estado: str) -> None:
    await ejecutar.procedimiento("sp_habitaciones_cambiar_estado", id_actor, id_habitacion, estado)


async def cambiar_activo(id_actor: int, id_habitacion: int, activo: bool) -> None:
    await ejecutar.procedimiento("sp_habitaciones_cambiar_activo", id_actor, id_habitacion, activo)


async def listar(id_actor: int, id_hotel: int, estado: str | None, id_tipo: int | None, busqueda: str | None,
                 incluir_inactivas: bool, pagina: int, tamano: int, orden: str, direccion: str) -> list[dict]:
    return await ejecutar.filas("sp_habitaciones_listar", id_actor, id_hotel, estado, id_tipo, busqueda,
                                incluir_inactivas, pagina, tamano, orden, direccion)