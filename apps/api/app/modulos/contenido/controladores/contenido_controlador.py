from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.contenido_esquema import (
    ContenidoConsulta,
    GuardarContenidoEsquema,
    PublicadoEsquema,
)
from ..servicios import contenido_servicio as servicio

_SIN_CONVERTIR = frozenset({"valor"})


async def obtener_publico(slug: str, pagina: str):
    return respuesta("Contenido obtenido correctamente", await servicio.obtener_publico(slug, pagina), _SIN_CONVERTIR)


async def listar(q: Annotated[ContenidoConsulta, Query()], actor: ActorDep):
    return respuesta("Contenido obtenido correctamente", await servicio.listar(actor.id_usuario, q), _SIN_CONVERTIR)


async def guardar(datos: GuardarContenidoEsquema, actor: ActorDep):
    return respuesta("Contenido guardado correctamente", await servicio.guardar(actor.id_usuario, datos))


async def cambiar_publicado(id_contenido_web: int, datos: PublicadoEsquema, actor: ActorDep):
    return respuesta(
        "Contenido publicado correctamente" if datos.publicado else "Contenido despublicado correctamente",
        await servicio.cambiar_publicado(actor.id_usuario, id_contenido_web, datos.publicado))