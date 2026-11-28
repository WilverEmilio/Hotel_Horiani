from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.bitacora_esquema import BitacoraConsulta
from ..servicios import bitacora_servicio as servicio

_SIN_CONVERTIR = frozenset({"valor_anterior", "valor_nuevo"})


async def listar(q: Annotated[BitacoraConsulta, Query()], actor: ActorDep):
    return respuesta("Bitácora obtenida correctamente", await servicio.listar(actor.id_usuario, q), _SIN_CONVERTIR)


async def catalogo(actor: ActorDep):
    return respuesta("Catálogo obtenido correctamente", await servicio.catalogo(actor.id_usuario))


async def historial_registro(entidad: str, id_registro: str, actor: ActorDep):
    return respuesta("Historial obtenido correctamente",
                     await servicio.historial_registro(actor.id_usuario, entidad, id_registro), _SIN_CONVERTIR)