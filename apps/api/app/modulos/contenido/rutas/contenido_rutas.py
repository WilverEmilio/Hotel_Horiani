from fastapi import APIRouter

from ..controladores import contenido_controlador as c

rutas_contenido_publico = APIRouter(prefix="/publico", tags=["Público"])
rutas_contenido_publico.add_api_route("/hoteles/{slug}/contenido/{pagina}", c.obtener_publico, methods=["GET"],
                                      summary="Contenido publicado de una página del hotel")

rutas_contenido = APIRouter(prefix="/contenido", tags=["Contenido web"])
r = rutas_contenido
r.add_api_route("", c.listar, methods=["GET"], summary="Todo el contenido (publicado o no) para el editor")
r.add_api_route("", c.guardar, methods=["PUT"], summary="Crear o reemplazar un bloque de contenido")
r.add_api_route("/{id_contenido_web}/publicado", c.cambiar_publicado, methods=["PATCH"],
                summary="Publicar o despublicar")