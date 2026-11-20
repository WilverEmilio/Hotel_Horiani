import psycopg
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

_pool: AsyncConnectionPool | None = None

async def _configurar_conexion(conn: psycopg.AsyncConnection) -> None:
    await conn.set_autocommit(True)
    await conn.execute("Set time zone 'America/Guatemala'")
    await conn.set_autocommit(False)
    

async def abrir_conexion(dsn: str, minimo: int, maximo: int) -> None:
    global _pool
    _pool = AsyncConnectionPool(
        dsn,
        min_size = minimo,
        max_size = maximo,
        kwargs = {"row_factory": dict_row},
        configure = _configurar_conexion,
        open = False,
    )
    await _pool.open(wait = True, timeout=15)
    
async def cerrar_conexion() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None
        
def obtener_pool() -> AsyncConnectionPool:
    if _pool is None:
        raise RuntimeError('La conexión a la base de datos no está iniciada')
    return _pool

async def conexion_disponible() -> bool:
    if _pool is None: 
        return False
    try:
        async with _pool.connection(timeout=3) as conn:
            await conn.execute('SELECT 1')
        return True
    except Exception: 
        return False