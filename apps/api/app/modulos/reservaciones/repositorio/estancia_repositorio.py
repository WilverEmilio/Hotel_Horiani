from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def hacer_checkin(id_actor: int, id_reservacion: int) -> dict:
    return await ejecutar.fila("sp_reservaciones_hacer_checkin", id_actor, id_reservacion)


async def hacer_checkout(id_actor: int, id_reservacion: int) -> dict:
    return await ejecutar.fila("sp_reservaciones_hacer_checkout", id_actor, id_reservacion)


async def marcar_no_presentado(id_actor: int, id_reservacion: int, observacion: str | None) -> dict:
    return await ejecutar.fila("sp_reservaciones_marcar_no_presentado", id_actor, id_reservacion, observacion)