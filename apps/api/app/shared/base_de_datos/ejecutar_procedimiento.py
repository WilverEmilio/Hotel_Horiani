import contextvars
import asyncio
import logging
import re
from typing import Any

import psycopg
from psycopg import sql
from psycopg.types.json import Jsonb

from ...config.base_de_datos import obtener_pool
from ..errores.catalogo_errores import traducir_error_bd

log = logging.getLogger('horiani.bd')

ip_actual: contextvars.ContextVar[str | None] = contextvars.ContextVar('ip_actual', default=None)

_NOMBRE_SP = re.compile(r"^sp_[a-z0-9_]+$")
_REINTENTABLES = (psycopg.errors.DeadlockDetected, psycopg.errors.SerializationFailure)

def json(valor: Any) -> Jsonb:
    """Envuelve un dict o lista para pasarlo a un parámetro JSONB."""
    return Jsonb(valor)


def _consulta(nombre_sp: str, cantidad_args: int) -> sql.Composed:
    if not _NOMBRE_SP.match(nombre_sp):
        raise ValueError(f"Nombre de stored procedure inválido: {nombre_sp}")
    marcadores = sql.SQL(", ").join(sql.Placeholder() * cantidad_args)
    return sql.SQL("SELECT * FROM {}({})").format(sql.Identifier(nombre_sp), marcadores)


async def _llamar(nombre_sp: str, args: tuple) -> list[dict]:
    consulta = _consulta(nombre_sp, len(args))
    for intento in (1, 2):
        try:
            async with obtener_pool().connection() as conn, conn.transaction():
                ip = ip_actual.get()
                if ip: 
                    await conn.execute("SELECT set_config('horiani.ip', %s, true)", (ip,))
                cur = await conn.execute(consulta, args)
                return await cur.fetchall() if cur.description else []
        except _REINTENTABLES as e:
            if intento == 1:
                log.warning("Reintentando %s por %s", nombre_sp, type(e).__name__)
                await asyncio.sleep(0.05)
                continue
            raise traducir_error_bd(e) from e
        except psycopg.Error as e:
            raise traducir_error_bd(e) from e
    return []


async def filas(nombre_sp: str, *args) -> list[dict]:
    return await _llamar(nombre_sp, args)


async def fila(nombre_sp: str, *args) -> dict | None:
    resultado = await _llamar(nombre_sp, args)
    return resultado[0] if resultado else None


async def valor(nombre_sp: str, *args) -> Any:
    resultado = await _llamar(nombre_sp, args)
    return next(iter(resultado[0].values())) if resultado else None


async def procedimiento(nombre_sp: str, *args) -> None:
    await _llamar(nombre_sp, args)