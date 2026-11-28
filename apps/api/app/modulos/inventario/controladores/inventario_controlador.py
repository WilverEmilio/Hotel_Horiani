from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.inventario_esquema import (
    ActualizarArticuloEsquema,
    BajaEsquema,
    BlancosEsquema,
    ConsumoEsquema,
    ConteoEsquema,
    CrearArticuloEsquema,
    CrearCategoriaEsquemaU,
    EntradaEsquema,
    ExistenciasConsulta,
    MovimientosConsulta,
)
from ..servicios import inventario_servicio as servicio


async def listar_categorias(actor: ActorDep):
    return respuesta("Categorías obtenidas correctamente", await servicio.listar_categorias(actor.id_usuario))


async def crear_categoria(datos: CrearCategoriaEsquemaU, actor: ActorDep):
    return respuesta("Categoría creada correctamente", await servicio.crear_categoria(actor.id_usuario, datos.nombre))


async def crear_articulo(datos: CrearArticuloEsquema, actor: ActorDep):
    return respuesta("Artículo creado correctamente", await servicio.crear_articulo(actor.id_usuario, datos))


async def actualizar_articulo(id_articulo: int, datos: ActualizarArticuloEsquema, actor: ActorDep):
    return respuesta("Artículo actualizado correctamente",
                     await servicio.actualizar_articulo(actor.id_usuario, id_articulo, datos))


async def registrar_entrada(id_articulo: int, datos: EntradaEsquema, actor: ActorDep):
    return respuesta("Entrada registrada correctamente",
                     await servicio.registrar_entrada(actor.id_usuario, id_articulo, datos))


async def registrar_conteo(id_articulo: int, datos: ConteoEsquema, actor: ActorDep):
    return respuesta("Conteo registrado correctamente",
                     await servicio.registrar_conteo(actor.id_usuario, id_articulo, datos))


async def registrar_consumo(id_articulo: int, datos: ConsumoEsquema, actor: ActorDep):
    return respuesta("Consumo registrado correctamente",
                     await servicio.registrar_consumo(actor.id_usuario, id_articulo, datos))


async def dar_baja(id_articulo: int, datos: BajaEsquema, actor: ActorDep):
    return respuesta("Baja registrada correctamente", await servicio.dar_baja(actor.id_usuario, id_articulo, datos))


async def colocar_blancos(id_habitacion: int, datos: BlancosEsquema, actor: ActorDep):
    return respuesta("Blancos colocados correctamente",
                     await servicio.colocar_blancos(actor.id_usuario, id_habitacion, datos.items))


async def listar_existencias(q: Annotated[ExistenciasConsulta, Query()], actor: ActorDep):
    return respuesta("Existencias obtenidas correctamente", await servicio.listar_existencias(actor.id_usuario, q))


async def listar_movimientos(q: Annotated[MovimientosConsulta, Query()], actor: ActorDep):
    return respuesta("Movimientos obtenidos correctamente", await servicio.listar_movimientos(actor.id_usuario, q))


async def alertas(id_hotel: Annotated[int, Query(alias="idHotel")], actor: ActorDep):
    return respuesta("Alertas obtenidas correctamente", await servicio.alertas(actor.id_usuario, id_hotel))