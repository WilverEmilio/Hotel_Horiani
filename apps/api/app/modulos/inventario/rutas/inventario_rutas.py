from fastapi import APIRouter

from ..controladores import inventario_controlador as c
from ..controladores import lavanderia_controlador as lavanderia

rutas_inventario = APIRouter(tags=["Inventario y lavandería"])
r = rutas_inventario

r.add_api_route("/inventario/categorias", c.listar_categorias, methods=["GET"], summary="Categorías activas")
r.add_api_route("/inventario/categorias", c.crear_categoria, methods=["POST"], status_code=201,
                summary="Crear categoría")
r.add_api_route("/inventario/articulos", c.crear_articulo, methods=["POST"], status_code=201,
                summary="Crear artículo (existencias en cero)")
r.add_api_route("/inventario/articulos/{id_articulo}", c.actualizar_articulo, methods=["PUT"],
                summary="Editar artículo")
r.add_api_route("/inventario/articulos/{id_articulo}/entradas", c.registrar_entrada, methods=["POST"],
                status_code=201, summary="Compra o recepción a bodega")
r.add_api_route("/inventario/articulos/{id_articulo}/conteos", c.registrar_conteo, methods=["POST"],
                status_code=201, summary="Conteo físico (registra el ajuste por la diferencia)")
r.add_api_route("/inventario/articulos/{id_articulo}/consumos", c.registrar_consumo, methods=["POST"],
                status_code=201, summary="Salida de un insumo de bodega")
r.add_api_route("/inventario/articulos/{id_articulo}/bajas", c.dar_baja, methods=["POST"], status_code=201,
                summary="Baja por daño o pérdida")
r.add_api_route("/habitaciones/{id_habitacion}/blancos", c.colocar_blancos, methods=["POST"], status_code=201,
                summary="Limpieza coloca blancos limpios en una habitación")
r.add_api_route("/inventario/existencias", c.listar_existencias, methods=["GET"],
                summary="Existencias por ubicación con alerta de mínimo")
r.add_api_route("/inventario/movimientos", c.listar_movimientos, methods=["GET"], summary="Kardex")
r.add_api_route("/inventario/alertas", c.alertas, methods=["GET"], summary="Artículos bajo el mínimo en bodega")

r.add_api_route("/lavanderia/lotes", lavanderia.recibir_lote, methods=["POST"], status_code=201,
                summary="Recibir blancos sucios de las habitaciones")
r.add_api_route("/lavanderia/lotes", lavanderia.listar_lotes, methods=["GET"],
                summary="Lotes con piezas recibidas, devueltas y faltantes")
r.add_api_route("/lavanderia/lotes/{id_lote}", lavanderia.obtener_lote, methods=["GET"], summary="Detalle de un lote")
r.add_api_route("/lavanderia/lotes/{id_lote}/devolver", lavanderia.devolver_lote, methods=["POST"],
                summary="Devolver el lote a bodega (registra faltantes)")