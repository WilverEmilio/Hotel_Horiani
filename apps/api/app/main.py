"""Punto de entrada: uv run fastapi dev app/main.py"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from .aplicacion import crear_aplicacion
from .config.base_de_datos import abrir_conexion, cerrar_conexion
from .config.entorno import obtener_configuracion
from .job.tareas_programadas import detener_tareas, iniciar_tareas
from .semillas.usuarios_prueba import contrasenas_de_prueba

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def ciclo_de_vida(_: FastAPI):
    conf = obtener_configuracion()
    await abrir_conexion(conf.dsn, conf.db_pool_min, conf.db_pool_max)
    await contrasenas_de_prueba(conf)
    if conf.tareas_activas:
        iniciar_tareas()
    try:
        yield
    finally:
        detener_tareas()
        await cerrar_conexion()


app = crear_aplicacion(ciclo_de_vida)