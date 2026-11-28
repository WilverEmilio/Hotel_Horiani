from ....shared.utilidades.respuesta import paginar
from ..esquemas.bitacora_esquema import BitacoraConsulta
from ..repositorios import bitacora_repositorio as repositorio


async def listar(id_actor: int, q: BitacoraConsulta) -> dict:
    filas = await repositorio.listar(id_actor, q.id_hotel, q.modulo, q.entidad, q.id_registro, q.id_usuario,
                                     q.accion, q.fecha_desde, q.fecha_hasta, q.busqueda, q.pagina,
                                     q.registros_por_pagina)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def historial_registro(id_actor: int, entidad: str, id_registro: str) -> list[dict]:
    return await repositorio.historial_registro(id_actor, entidad, id_registro)


async def catalogo(id_actor: int) -> list[dict]:
    return await repositorio.catalogo(id_actor)