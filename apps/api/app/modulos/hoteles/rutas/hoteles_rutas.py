from fastapi import APIRouter

from ..controladores import hoteles_controlador as c

rutas_hoteles_publico = APIRouter(prefix="/publico/hoteles", tags=["Público"])
rutas_hoteles_publico.add_api_route("", c.listar_publico, methods=["GET"], summary="Hoteles activos")
rutas_hoteles_publico.add_api_route("/{slug}", c.obtener_publico, methods=["GET"],
                                    summary="Hotel por slug, con carrusel y galería")