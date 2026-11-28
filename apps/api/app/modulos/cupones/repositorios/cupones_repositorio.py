"""Stored procedures de cupones (script 030)."""
from datetime import date
from decimal import Decimal

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def crear(id_actor: int, codigo: str, descripcion: str | None, tipo: str, valor: Decimal, inicio: date,
                fin: date, monto_minimo: Decimal, limite_total: int | None, limite_cliente: int | None,
                id_hotel: int | None, id_tipo: int | None) -> int:
    return await ejecutar.valor("sp_cupones_crear", id_actor, codigo, descripcion, tipo, valor, inicio, fin,
                                monto_minimo, limite_total, limite_cliente, id_hotel, id_tipo)


async def actualizar(id_actor: int, id_cupon: int, codigo: str, descripcion: str | None, tipo: str, valor: Decimal,
                     inicio: date, fin: date, monto_minimo: Decimal, limite_total: int | None,
                     limite_cliente: int | None, id_hotel: int | None, id_tipo: int | None, activo: bool) -> None:
    await ejecutar.procedimiento("sp_cupones_actualizar", id_actor, id_cupon, codigo, descripcion, tipo, valor, inicio,
                                 fin, monto_minimo, limite_total, limite_cliente, id_hotel, id_tipo, activo)


async def listar(id_actor: int, id_hotel: int | None, busqueda: str | None, estado: str | None, pagina: int,
                 tamano: int) -> list[dict]:
    return await ejecutar.filas("sp_cupones_listar", id_actor, id_hotel, busqueda, estado, pagina, tamano)


async def obtener(id_actor: int, id_cupon: int) -> dict | None:
    return await ejecutar.fila("sp_cupones_obtener", id_actor, id_cupon)


async def vista_previa(id_actor: int, codigo: str, id_hotel: int, entrada: date, salida: date,
                       habitaciones: list[dict], id_cliente: int | None) -> dict:
    return await ejecutar.fila("sp_cupones_vista_previa", id_actor, codigo, id_hotel, entrada, salida,
                               ejecutar.json(habitaciones), id_cliente)