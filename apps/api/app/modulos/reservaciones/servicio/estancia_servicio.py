from ..repositorio import estancia_repositorio as repositorio


async def hacer_checkin(id_actor: int, id_reservacion: int) -> dict:
    return await repositorio.hacer_checkin(id_actor, id_reservacion)


async def hacer_checkout(id_actor: int, id_reservacion: int) -> dict:
    return await repositorio.hacer_checkout(id_actor, id_reservacion)


async def marcar_no_presentado(id_actor: int, id_reservacion: int, observacion: str | None) -> dict:
    return await repositorio.marcar_no_presentado(id_actor, id_reservacion, observacion)