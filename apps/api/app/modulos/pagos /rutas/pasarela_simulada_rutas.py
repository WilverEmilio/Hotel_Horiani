from fastapi import APIRouter

from ..controladores import pasarela_simulada_controlador as c

rutas_pasarela_simulada = APIRouter(prefix="/pasarela-simulada", tags=["Pasarela simulada (desarrollo)"])
rutas_pasarela_simulada.add_api_route("/pagar", c.pagina, methods=["GET"], summary="Página de pago de prueba")
rutas_pasarela_simulada.add_api_route("/pagar", c.decidir, methods=["POST"],
                                      summary="Simula la respuesta del banco y envía el aviso firmado")