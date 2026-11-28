from ..esquemas.contenido_esquema import ContenidoConsulta, GuardarContenidoEsquema
from ..repositorios import contenido_repositorio as repositorio


async def obtener_publico(slug: str, pagina: str) -> list[dict]:
    return await repositorio.obtener_publico(slug, pagina)


async def guardar(id_actor: int, d: GuardarContenidoEsquema) -> dict:
    id_contenido = await repositorio.guardar(id_actor, d.id_hotel, d.pagina, d.seccion, d.clave, d.tipo, d.valor,
                                             d.orden, d.publicado)
    return {"id_contenido_web": id_contenido}


async def cambiar_publicado(id_actor: int, id_contenido: int, publicado: bool) -> dict:
    await repositorio.cambiar_publicado(id_actor, id_contenido, publicado)
    return {"id_contenido_web": id_contenido, "publicado": publicado}


async def listar(id_actor: int, q: ContenidoConsulta) -> list[dict]:
    return await repositorio.listar(id_actor, q.id_hotel, q.pagina)