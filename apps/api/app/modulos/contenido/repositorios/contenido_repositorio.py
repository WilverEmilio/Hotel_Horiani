from typing import Any

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def obtener_publico(slug: str, pagina: str) -> list[dict]:
    return await ejecutar.filas("sp_contenido_obtener_publico", slug, pagina)


async def guardar(id_actor: int, id_hotel: int | None, pagina: str, seccion: str, clave: str, tipo: str, valor: Any,
                  orden: int, publicado: bool) -> int:
    return await ejecutar.valor("sp_contenido_guardar", id_actor, id_hotel, pagina, seccion, clave, tipo,
                                ejecutar.json(valor), orden, publicado)


async def cambiar_publicado(id_actor: int, id_contenido: int, publicado: bool) -> None:
    await ejecutar.procedimiento("sp_contenido_cambiar_publicado", id_actor, id_contenido, publicado)


async def listar(id_actor: int, id_hotel: int | None, pagina: str | None) -> list[dict]:
    return await ejecutar.filas("sp_contenido_listar", id_actor, id_hotel, pagina)