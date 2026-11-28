import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from ..modulos.mantenimiento.repositorios.matenimiento_repositorio import (
    sincronizar_estados,
)
from ..modulos.reservaciones.repositorio.reservaciones_repositorio import (
    expirar_pendientes,
)

log = logging.getLogger("horiani.jobs")
ZONA = "America/Guatemala"
_programador: AsyncIOScheduler | None = None


async def expirar_reservaciones() -> None:
    try:
        n = await expirar_pendientes()
        if n:
            log.info("Reservaciones vencidas por falta de pago: %s", n)
    except Exception:
        log.exception("Falló sp_reservaciones_expirar_pendientes")


async def sincronizar_mantenimiento() -> None:
    try:
        log.info("Habitaciones pasadas a mantenimiento hoy: %s", await sincronizar_estados())
    except Exception:
        log.exception("Falló sp_mantenimiento_sincronizar_estados")


def iniciar_tareas() -> None:
    global _programador
    _programador = AsyncIOScheduler(timezone=ZONA)
    _programador.add_job(expirar_reservaciones, IntervalTrigger(minutes=1), id="expirar_reservaciones",
                         max_instances=1, coalesce=True)
    _programador.add_job(sincronizar_mantenimiento, CronTrigger(hour=0, minute=5, timezone=ZONA),
                         id="sincronizar_mantenimiento", max_instances=1, coalesce=True, misfire_grace_time=3600)
    _programador.start()
    log.info("Tareas programadas iniciadas")


def detener_tareas() -> None:
    global _programador
    if _programador:
        _programador.shutdown(wait=False)
        _programador = None