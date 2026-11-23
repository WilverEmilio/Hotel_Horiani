import logging

from ..config.entorno import Configuracion
from ..modulos.autenticacion.repositorios.autenticacion_repositorio import (
    establecer_contrasena_inicial,
)
from ..shared.utilidades.contrasena import hashear_contrasena

log = logging.getLogger("horiani.semillas")

CORREOS_PERSONAL = [
    "admin@horiani.test", "oficinista@horiani.test", "recepcion@horiani.test", "recepcion2@horiani.test",
    "limpieza@horiani.test", "lavanderia@horiani.test", "recepcion.sede2@horiani.test",
    "recepcion.sede3@horiani.test", "recepcion.sede4@horiani.test", "cliente@horiani.test",
]
CORREOS_CLIENTES = [f"cliente{n}@correo.test" for n in range(1, 81)]


async def contrasenas_de_prueba(conf: Configuracion) -> None:
    if not (conf.es_desarrollo and conf.cargar_datos_prueba):
        return
    contrasena = conf.contrasena_datos_prueba.get_secret_value()
    if len(contrasena) < 8:
        log.warning("CONTRASENA_DATOS_PRUEBA vacía o menor a 8 caracteres: los usuarios de prueba quedan sin contraseña")
        return
    hash_ = await hashear_contrasena(contrasena)   # un solo hash para todos (solo en desarrollo)
    definidas = 0
    for correo in CORREOS_PERSONAL + CORREOS_CLIENTES:
        if await establecer_contrasena_inicial(correo, hash_):
            definidas += 1
    if definidas:
        log.info("Contraseña de prueba definida para %s usuarios", definidas)