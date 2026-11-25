from uuid import UUID

from ....config.entorno import obtener_configuracion
from ....shared.utilidades.mapeo import a_snake
from ....shared.utilidades.respuesta import paginar
from ..esquemas.pagos_esquema import PagoEnHotelEsquema, PagosConsulta, ReembolsoEsquema
from ..repositorios import pagos_repositorio as repositorio
from .pasarela_simulada_servicio import obtener_pasarela


async def iniciar_anticipo(id_actor: int, id_reservacion: int, llave: UUID) -> dict:
    pasarela = obtener_pasarela()
    fila = dict(await repositorio.iniciar_anticipo(id_actor, id_reservacion, pasarela.nombre, llave))
    if fila["estado"] == "pendiente":
        fila["url_pago"] = pasarela.crear_cobro(fila["id_pago"], id_reservacion, fila["monto"]).url_pago
    return fila


async def procesar_aviso(nombre_pasarela: str, cuerpo: bytes, encabezados: dict[str, str]) -> dict:
    pasarela = obtener_pasarela(nombre_pasarela)
    aviso = pasarela.verificar_aviso(cuerpo, encabezados)
    return await repositorio.confirmar_pasarela(pasarela.nombre, aviso.id_evento, aviso.tipo_evento,
                                                aviso.contenido, aviso.id_pago, aviso.referencia, aviso.monto,
                                                aviso.aprobado)


async def registrar_en_hotel(id_actor: int, id_reservacion: int, d: PagoEnHotelEsquema, llave: UUID) -> dict:
    return await repositorio.registrar_en_hotel(id_actor, id_reservacion, d.tipo, d.metodo, d.monto, llave)


async def reembolsar(id_actor: int, id_pago: int, d: ReembolsoEsquema, llave: UUID) -> dict:
    return await repositorio.reembolsar(id_actor, id_pago, d.monto, d.motivo, d.referencia_pasarela, llave)


async def listar_por_reservacion(id_actor: int, id_reservacion: int) -> list[dict]:
    return await repositorio.listar_por_reservacion(id_actor, id_reservacion)


async def listar(id_actor: int, q: PagosConsulta) -> dict:
    filas = await repositorio.listar(id_actor, q.id_hotel, q.tipo, q.metodo, q.estado, q.fecha_desde, q.fecha_hasta,
                                     q.pagina, q.registros_por_pagina, a_snake(q.ordenar_por), q.direccion)
    return paginar(filas, q.pagina, q.registros_por_pagina)


def url_resultado(id_reservacion: int, resultado: str) -> str:
    return f"{obtener_configuracion().url_web.rstrip('/')}/mis-reservaciones/{id_reservacion}?pago={resultado}"