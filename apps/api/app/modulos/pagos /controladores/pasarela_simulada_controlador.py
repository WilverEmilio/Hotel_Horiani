"""Página de pago de prueba (solo fuera de producción)."""
import json
import uuid
from html import escape
from typing import Annotated, Literal

from fastapi import Form
from fastapi.responses import HTMLResponse, RedirectResponse

from ....shared.errores.error_aplicacion import ErrorAplicacion
from ..servicios.pagos_servicio import procesar_aviso, url_resultado
from ..servicios.pasarela_simulada_servicio import firmar, obtener_pasarela

_PLANTILLA = """<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pasarela simulada</title>
<style>
 body{{font-family:system-ui,sans-serif;background:#f4f1ec;margin:0;display:grid;place-items:center;min-height:100vh}}
 main{{background:#fff;padding:2rem;border-radius:12px;max-width:380px;width:90%;box-shadow:0 4px 20px #0001}}
 h1{{font-size:1.1rem;margin:0 0 .25rem}} p{{color:#555;margin:.25rem 0}}
 .monto{{font-size:2rem;font-weight:700;margin:1rem 0}}
 .aviso{{background:#fff4d6;border-radius:8px;padding:.6rem;font-size:.85rem;color:#7a5b00}}
 form{{display:flex;gap:.5rem;margin-top:1.25rem}}
 button{{flex:1;padding:.8rem;border:0;border-radius:8px;font-size:1rem;cursor:pointer}}
 .ok{{background:#1f7a4d;color:#fff}} .no{{background:#e5e5e5}}
</style></head><body><main>
<h1>Hotel Horiani · Pago de anticipo</h1>
<p>Reservación #{id_reservacion} · Pago #{id_pago}</p>
<div class="monto">Q{monto}</div>
<div class="aviso">Pasarela de prueba: no se cobra dinero real.</div>
<form method="post">
 <input type="hidden" name="d" value="{d}"><input type="hidden" name="f" value="{f}">
 <button class="no" name="decision" value="rechazar">Rechazar</button>
 <button class="ok" name="decision" value="aprobar">Aprobar pago</button>
</form>
</main></body></html>"""


async def pagina(d: str, f: str):
    datos = obtener_pasarela("simulada").leer_enlace(d, f)
    return HTMLResponse(_PLANTILLA.format(id_reservacion=int(datos["id_reservacion"]), id_pago=int(datos["id_pago"]),
                                          monto=escape(datos["monto"]), d=escape(d), f=escape(f)))


async def decidir(d: Annotated[str, Form()], f: Annotated[str, Form()],
                  decision: Annotated[Literal["aprobar", "rechazar"], Form()]):
    """Simula al banco: arma el aviso, lo firma y lo procesa por el MISMO camino que el webhook real."""
    datos = obtener_pasarela("simulada").leer_enlace(d, f)
    aprobado = decision == "aprobar"
    aviso = json.dumps({
        "id_evento": str(uuid.uuid4()),
        "tipo_evento": "cobro.aprobado" if aprobado else "cobro.rechazado",
        "id_pago": int(datos["id_pago"]),
        "referencia": f"SIM-{uuid.uuid4().hex[:10].upper()}",
        "monto": datos["monto"],
        "aprobado": aprobado,
    }).encode()
    try:
        resultado = await procesar_aviso("simulada", aviso, {"x-firma": firmar(aviso)})
        estado = resultado["estado_pago"] if resultado else "error"
    except ErrorAplicacion:
        estado = "error"
    return RedirectResponse(url_resultado(int(datos["id_reservacion"]), estado), status_code=303)