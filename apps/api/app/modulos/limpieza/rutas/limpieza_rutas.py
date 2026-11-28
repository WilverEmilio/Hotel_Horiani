from fastapi import APIRouter

from ..controladores import limpieza_controlador as c

rutas_limpieza = APIRouter(prefix="/limpieza/tareas", tags=["Limpieza"])
r = rutas_limpieza
r.add_api_route("", c.crear_tarea, methods=["POST"], status_code=201, summary="Crear tarea manual de limpieza")
r.add_api_route("", c.listar_tareas, methods=["GET"], summary="Tareas (abiertas primero, por llegada más próxima)")
r.add_api_route("/{id_tarea}/asignar", c.asignar_tarea, methods=["PATCH"], summary="Asignar tarea")
r.add_api_route("/{id_tarea}/tomar", c.tomar_tarea, methods=["POST"], summary="Tomar la tarea")
r.add_api_route("/{id_tarea}/completar", c.completar_tarea, methods=["POST"],
                summary="Completar la tarea (la habitación queda disponible)")