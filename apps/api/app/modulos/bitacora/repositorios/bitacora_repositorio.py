from datetime import date

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def listar(id_actor: int, id_hotel: int | None, modulo: str | None, entidad: str | None,
                 id_registro: str | None, id_usuario: int | None, accion: str | None, desde: date | None,
                 hasta: date | None, busqueda: str | None, pagina: int, tamano: int) -> list[dict]:
    return await ejecutar.filas("sp_bitacora_listar", id_actor, id_hotel, modulo, entidad, id_registro, id_usuario,
                                accion, desde, hasta, busqueda, pagina, tamano)


async def historial_registro(id_actor: int, entidad: str, id_registro: str) -> list[dict]:
    return await ejecutar.filas("sp_bitacora_historial_registro", id_actor, entidad, id_registro)


async def catalogo(id_actor: int) -> list[dict]:
    return await ejecutar.filas("sp_bitacora_catalogo", id_actor)