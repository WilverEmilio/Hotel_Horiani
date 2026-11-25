from datetime import date
from decimal import Decimal
from uuid import UUID

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def iniciar_anticipo(id_actor: int, id_reservacion: int, pasarela: str, llave: UUID) -> dict:
    return await ejecutar.fila("sp_pagos_iniciar_anticipo", id_actor, id_reservacion, pasarela, llave)


async def confirmar_pasarela(pasarela: str, id_evento: str, tipo_evento: str, contenido: dict, id_pago: int,
                             referencia: str | None, monto: Decimal, aprobado: bool) -> dict:
    return await ejecutar.fila("sp_pagos_confirmar_pasarela", pasarela, id_evento, tipo_evento,
                               ejecutar.json(contenido), id_pago, referencia, monto, aprobado)


async def registrar_en_hotel(id_actor: int, id_reservacion: int, tipo: str, metodo: str, monto: Decimal,
                             llave: UUID) -> dict:
    return await ejecutar.fila("sp_pagos_registrar_en_hotel", id_actor, id_reservacion, tipo, metodo, monto, llave)


async def reembolsar(id_actor: int, id_pago_origen: int, monto: Decimal, motivo: str, referencia: str | None,
                     llave: UUID) -> dict:
    return await ejecutar.fila("sp_pagos_reembolsar", id_actor, id_pago_origen, monto, motivo, referencia, llave)


async def listar_por_reservacion(id_actor: int, id_reservacion: int) -> list[dict]:
    return await ejecutar.filas("sp_pagos_listar_por_reservacion", id_actor, id_reservacion)


async def listar(id_actor: int, id_hotel: int, tipo: str | None, metodo: str | None, estado: str | None,
                 desde: date | None, hasta: date | None, pagina: int, tamano: int, orden: str,
                 direccion: str) -> list[dict]:
    return await ejecutar.filas("sp_pagos_listar", id_actor, id_hotel, tipo, metodo, estado, desde, hasta, pagina,
                                tamano, orden, direccion)