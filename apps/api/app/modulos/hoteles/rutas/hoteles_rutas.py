from fastapi import APIRouter

from ..controladores import hoteles_controlador as c

rutas_hoteles = APIRouter(prefix='/hoteles', tags=['Hoteles'])
r = rutas_hoteles

rutas_hoteles_publico = APIRouter(prefix="/publico/hoteles", tags=["Público"])
rutas_hoteles_publico.add_api_route("", c.listar_publico, methods=["GET"], summary="Hoteles activos")
rutas_hoteles_publico.add_api_route("/{slug}", c.obtener_publico, methods=["GET"],
                                    summary="Hotel por slug, con carrusel y galería")

r.add_api_route("", c.crear, methods=["POST"], status_code=201, summary="Crear hotel (con configuración por defecto)")
r.add_api_route("/{id_hotel}", c.actualizar, methods=["PUT"], summary="Editar o desactivar un hotel")
r.add_api_route("/{id_hotel}/configuracion", c.obtener_configuracion, methods=["GET"], summary="Parámetros del hotel")
r.add_api_route("/{id_hotel}/configuracion", c.actualizar_configuracion, methods=["PUT"],
                summary="Modificar parámetros del hotel")
r.add_api_route("/{id_hotel}/imagenes", c.agregar_imagen, methods=["POST"], status_code=201,
                summary="Agregar imagen al carrusel o galería")
r.add_api_route("/imagenes/{id_hotel_imagen}", c.quitar_imagen, methods=["DELETE"], summary="Quitar una imagen del hotel")
r.add_api_route("/{id_hotel}/imagenes/orden", c.ordenar_imagenes, methods=["PUT"],
                summary="Reordenar imágenes de una sección")