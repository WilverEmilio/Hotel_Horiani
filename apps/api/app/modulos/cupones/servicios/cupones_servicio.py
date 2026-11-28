from ....shared.errores.error_aplicacion import ErrorAplicacion
from ....shared.utilidades.respuesta import paginar
from ...reservaciones.esquemas.reservaciones_esquema import habitaciones_para_bd
from ..esquemas.cupones_esquema import (
    ActualizarCuponEsquema,
    CrearCuponEsquema,
    CuponesConsulta,
    VistaPreviaEsquema,
)
from ..repositorios import cupones_repositorio as repositorio


async def crear(id_actor: int, d: CrearCuponEsquema) -> dict:
    id_cupon = await repositorio.crear(id_actor, d.codigo, d.descripcion, d.tipo, d.valor, d.fecha_inicio,
                                       d.fecha_fin, d.monto_minimo, d.limite_usos_total, d.limite_usos_cliente,
                                       d.id_hotel, d.id_tipo_habitacion)
    return {"id_cupon": id_cupon}


async def actualizar(id_actor: int, id_cupon: int, d: ActualizarCuponEsquema) -> dict:
    await repositorio.actualizar(id_actor, id_cupon, d.codigo, d.descripcion, d.tipo, d.valor, d.fecha_inicio,
                                 d.fecha_fin, d.monto_minimo, d.limite_usos_total, d.limite_usos_cliente,
                                 d.id_hotel, d.id_tipo_habitacion, d.activo)
    return {"id_cupon": id_cupon}


async def listar(id_actor: int, q: CuponesConsulta) -> dict:
    filas = await repositorio.listar(id_actor, q.id_hotel, q.busqueda, q.estado, q.pagina, q.registros_por_pagina)
    return paginar(filas, q.pagina, q.registros_por_pagina)


async def obtener(id_actor: int, id_cupon: int) -> dict:
    fila = await repositorio.obtener(id_actor, id_cupon)
    if not fila:
        raise ErrorAplicacion("El cupón no existe", "cupon_no_encontrado", 404)
    return fila


async def vista_previa(id_actor: int, d: VistaPreviaEsquema) -> dict:
    return await repositorio.vista_previa(id_actor, d.codigo, d.id_hotel, d.fecha_entrada, d.fecha_salida,
                                          habitaciones_para_bd(d.habitaciones), d.id_cliente)