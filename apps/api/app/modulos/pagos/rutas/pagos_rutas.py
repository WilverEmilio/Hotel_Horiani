from fastapi import APIRouter

from ..controladores import pagos_controladores as c

rutas_pagos = APIRouter(tags=["Pagos"])
r = rutas_pagos
r.add_api_route("/reservaciones/{id_reservacion}/pagos/anticipo", c.iniciar_anticipo, methods=["POST"],
                status_code=201, summary="Paso 1: iniciar el pago en línea del anticipo (devuelve la URL de la pasarela)")
r.add_api_route("/pagos/avisos/{pasarela}", c.recibir_aviso, methods=["POST"],
                summary="Paso 2: aviso (webhook) firmado de la pasarela")
r.add_api_route("/reservaciones/{id_reservacion}/pagos", c.registrar_en_hotel, methods=["POST"], status_code=201,
                summary="Registrar cobro en recepción (efectivo o tarjeta)")
r.add_api_route("/pagos/{id_pago}/reembolsos", c.reembolsar, methods=["POST"], status_code=201,
                summary="Registrar un reembolso ya ejecutado")
r.add_api_route("/reservaciones/{id_reservacion}/pagos", c.listar_por_reservacion, methods=["GET"],
                summary="Pagos de una reservación con total, pagado y saldo")
r.add_api_route("/pagos", c.listar, methods=["GET"], summary="Listado paginado de pagos del hotel")