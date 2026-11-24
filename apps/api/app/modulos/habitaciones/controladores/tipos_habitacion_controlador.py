from typing import Annotated

from fastapi import Query

from ....shared.esquemas.comunes import OrdenIdsEsquema
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.tipos_habitacion_esquema import (
    ActualizarTipoEsquema,
    CrearServicioEsquema,
    CrearTarifaEsquema,
    CrearTipoEsquema,
    ImagenTipoEsquema,
    PrecioBaseEsquema,
    ServiciosTipoEsquema,
    TarifasConsulta,
)
from ..servicios import tipos_habitaciones_servicio as servicio


async def listar_servicios_publico():
    return respuesta("Servicios obtenidos correctamente", await servicio.listar_servicios_publico())


async def crear_servicio(datos: CrearServicioEsquema, actor: ActorDep):
    return respuesta("Servicio creado correctamente", await servicio.crear_servicio(actor.id_usuario, datos))


async def listar_tipos_publico(id_hotel: int):
    return respuesta("Tipos de habitación obtenidos correctamente", await servicio.listar_tipos_publico(id_hotel))


async def crear_tipo(datos: CrearTipoEsquema, actor: ActorDep):
    return respuesta("Tipo de habitación creado correctamente", await servicio.crear_tipo(actor.id_usuario, datos))


async def actualizar_tipo(id_tipo_habitacion: int, datos: ActualizarTipoEsquema, actor: ActorDep):
    return respuesta("Tipo de habitación actualizado correctamente",
                     await servicio.actualizar_tipo(actor.id_usuario, id_tipo_habitacion, datos))


async def cambiar_precio_base(id_tipo_habitacion: int, datos: PrecioBaseEsquema, actor: ActorDep):
    return respuesta("Precio actualizado correctamente",
                     await servicio.cambiar_precio_base(actor.id_usuario, id_tipo_habitacion, datos.precio_base))


async def asignar_servicios(id_tipo_habitacion: int, datos: ServiciosTipoEsquema, actor: ActorDep):
    return respuesta("Servicios asignados correctamente",
                     await servicio.asignar_servicios(actor.id_usuario, id_tipo_habitacion, datos.ids_servicio))


async def listar_tarifas(id_tipo_habitacion: int, q: Annotated[TarifasConsulta, Query()], actor: ActorDep):
    return respuesta("Tarifas obtenidas correctamente",
                     await servicio.listar_tarifas(actor.id_usuario, id_tipo_habitacion, q.incluir_inactivas))


async def crear_tarifa(id_tipo_habitacion: int, datos: CrearTarifaEsquema, actor: ActorDep):
    return respuesta("Tarifa especial creada correctamente",
                     await servicio.crear_tarifa(actor.id_usuario, id_tipo_habitacion, datos))


async def desactivar_tarifa(id_tarifa_especial: int, actor: ActorDep):
    return respuesta("Tarifa especial desactivada correctamente",
                     await servicio.desactivar_tarifa(actor.id_usuario, id_tarifa_especial))


async def agregar_imagen(id_tipo_habitacion: int, datos: ImagenTipoEsquema, actor: ActorDep):
    return respuesta("Imagen agregada correctamente",
                     await servicio.agregar_imagen(actor.id_usuario, id_tipo_habitacion, datos))


async def quitar_imagen(id_tipo_habitacion_imagen: int, actor: ActorDep):
    return respuesta("Imagen quitada correctamente",
                     await servicio.quitar_imagen(actor.id_usuario, id_tipo_habitacion_imagen))


async def ordenar_imagenes(id_tipo_habitacion: int, datos: OrdenIdsEsquema, actor: ActorDep):
    return respuesta("Imágenes ordenadas correctamente",
                     await servicio.ordenar_imagenes(actor.id_usuario, id_tipo_habitacion, datos.ids))