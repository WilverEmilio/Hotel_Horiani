from ....shared.utilidades.mapeo import a_snake
from ....shared.utilidades.respuesta import paginar
from ..esquemas.inventario_esquema import (
    ActualizarArticuloEsquema,
    BajaEsquema,
    ConsumoEsquema,
    ConteoEsquema,
    CrearArticuloEsquema,
    EntradaEsquema,
    ExistenciasConsulta,
    ItemEsquema,
    MovimientosConsulta,
)
from ..repositorio import inventario_repositorio as repositorio


async def crear_categoria(id_actor: int, nombre: str) -> dict:
    return {"id_categoria_articulo": await repositorio.crear_categoria(id_actor, nombre)}


async def listar_categorias(id_actor: int) -> list[dict]:
    return await repositorio.listar_categorias(id_actor)


async def crear_articulo(id_actor: int, d: CrearArticuloEsquema) -> dict:
    id_articulo = await repositorio.crear_articulo(id_actor, d.id_hotel, d.id_categoria_articulo, d.nombre, d.clase,
                                                   d.unidad_medida, d.existencia_minima)
    return {"id_articulo": id_articulo}


async def actualizar_articulo(id_actor: int, id_articulo: int, d: ActualizarArticuloEsquema) -> dict:
    await repositorio.actualizar_articulo(id_actor, id_articulo, d.id_categoria_articulo, d.nombre, d.unidad_medida,
                                          d.existencia_minima, d.activo)
    return {"id_articulo": id_articulo}


async def registrar_entrada(id_actor: int, id_articulo: int, d: EntradaEsquema) -> dict:
    return await repositorio.registrar_entrada(id_actor, id_articulo, d.cantidad, d.motivo)


async def registrar_conteo(id_actor: int, id_articulo: int, d: ConteoEsquema) -> dict:
    return await repositorio.registrar_conteo(id_actor, id_articulo, d.ubicacion, d.cantidad_contada, d.motivo)


async def registrar_consumo(id_actor: int, id_articulo: int, d: ConsumoEsquema) -> dict:
    return await repositorio.registrar_consumo(id_actor, id_articulo, d.cantidad, d.id_habitacion, d.motivo)


async def dar_baja(id_actor: int, id_articulo: int, d: BajaEsquema) -> dict:
    return {"id_movimiento": await repositorio.dar_baja(id_actor, id_articulo, d.ubicacion, d.cantidad, d.motivo)}


async def colocar_blancos(id_actor: int, id_habitacion: int, items: list[ItemEsquema]) -> dict:
    items_bd = [i.model_dump(mode="json") for i in items]
    return {"movimientos": await repositorio.colocar_blancos(id_actor, id_habitacion, items_bd)}


async def listar_existencias(id_actor: int, q: ExistenciasConsulta) -> dict:
    filas = await repositorio.listar_existencias(id_actor, q.id_hotel, q.clase, q.busqueda, q.solo_bajo_minimo,
                                                 q.incluir_inactivos, q.pagina, q.registros_por_pagina,
                                                 a_snake(q.ordenar_por), q.direccion)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def listar_movimientos(id_actor: int, q: MovimientosConsulta) -> dict:
    filas = await repositorio.listar_movimientos(id_actor, q.id_hotel, q.id_articulo, q.tipo, q.fecha_desde,
                                                 q.fecha_hasta, q.pagina, q.registros_por_pagina)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def alertas(id_actor: int, id_hotel: int) -> list[dict]:
    return await repositorio.alertas(id_actor, id_hotel)