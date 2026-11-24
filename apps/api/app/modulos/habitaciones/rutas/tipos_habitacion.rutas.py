from fastapi import APIRouter

from ..controladores import tipos_habitacion_controlador as c

rutas_tipos_habitacion_publico = APIRouter(prefix="/publico", tags=["Público"])
p = rutas_tipos_habitacion_publico
p.add_api_route("/servicios", c.listar_servicios_publico, methods=["GET"], summary="Catálogo de servicios")
p.add_api_route("/hoteles/{id_hotel}/tipos-habitacion", c.listar_tipos_publico, methods=["GET"],
                summary="Tipos de habitación con precio, servicios e imágenes")

rutas_tipos_habitacion = APIRouter(tags=["Habitaciones"])
r = rutas_tipos_habitacion
r.add_api_route("/servicios", c.crear_servicio, methods=["POST"], status_code=201, summary="Agregar servicio al catálogo")
r.add_api_route("/tipos-habitacion", c.crear_tipo, methods=["POST"], status_code=201, summary="Crear tipo de habitación")
r.add_api_route("/tipos-habitacion/{id_tipo_habitacion}", c.actualizar_tipo, methods=["PUT"], summary="Editar tipo")
r.add_api_route("/tipos-habitacion/{id_tipo_habitacion}/precio", c.cambiar_precio_base, methods=["PUT"],
                summary="Cambiar precio base (no afecta reservaciones existentes)")
r.add_api_route("/tipos-habitacion/{id_tipo_habitacion}/servicios", c.asignar_servicios, methods=["PUT"],
                summary="Definir los servicios del tipo")
r.add_api_route("/tipos-habitacion/{id_tipo_habitacion}/tarifas", c.listar_tarifas, methods=["GET"],
                summary="Tarifas especiales del tipo")
r.add_api_route("/tipos-habitacion/{id_tipo_habitacion}/tarifas", c.crear_tarifa, methods=["POST"], status_code=201,
                summary="Crear tarifa especial por fechas")
r.add_api_route("/tarifas/{id_tarifa_especial}", c.desactivar_tarifa, methods=["DELETE"],
                summary="Desactivar tarifa especial")
r.add_api_route("/tipos-habitacion/{id_tipo_habitacion}/imagenes", c.agregar_imagen, methods=["POST"], status_code=201,
                summary="Agregar imagen al tipo")
r.add_api_route("/tipos-habitacion/imagenes/{id_tipo_habitacion_imagen}", c.quitar_imagen, methods=["DELETE"],
                summary="Quitar imagen del tipo")
r.add_api_route("/tipos-habitacion/{id_tipo_habitacion}/imagenes/orden", c.ordenar_imagenes, methods=["PUT"],
                summary="Reordenar imágenes del tipo")