import base64
import hashlib
import hmac
import json
import time
from decimal import Decimal, InvalidOperation

from ....config.entorno import obtener_configuracion
from ....shared.errores.error_aplicacion import ErrorAplicacion
from ..tipos.pasarela_tipo import Aviso, Cobro

VIGENCIA_ENLACE = 30 * 60  


def _secreto() -> bytes:
    conf = obtener_configuracion()
    propio = conf.pasarela_secreto_webhook.get_secret_value()
    if propio:
        return propio.encode()
    return hmac.new(conf.jwt_secreto.get_secret_value().encode(), b"pasarela-simulada", hashlib.sha256).digest()


def firmar(datos: bytes) -> str:
    return hmac.new(_secreto(), datos, hashlib.sha256).hexdigest()


def _a_b64(datos: bytes) -> str:
    return base64.urlsafe_b64encode(datos).decode().rstrip("=")


def _desde_b64(texto: str) -> bytes:
    return base64.urlsafe_b64decode(texto + "=" * (-len(texto) % 4))


class PasarelaSimulada:
    nombre = "simulada"

    def crear_cobro(self, id_pago: int, id_reservacion: int, monto: Decimal) -> Cobro:
        conf = obtener_configuracion()
        carga = json.dumps({"id_pago": id_pago, "id_reservacion": id_reservacion, "monto": str(monto),
                            "exp": int(time.time()) + VIGENCIA_ENLACE}, separators=(",", ":")).encode()
        d = _a_b64(carga)
        url = f"{conf.url_api.rstrip('/')}/api/v1/pasarela-simulada/pagar?d={d}&f={firmar(d.encode())}"
        return Cobro(url_pago=url)

    def leer_enlace(self, d: str, f: str) -> dict:
        """Valida que nadie haya cambiado el monto en la URL y que no haya vencido."""
        if not hmac.compare_digest(firmar(d.encode()), f):
            raise ErrorAplicacion("El enlace de pago no es válido", "enlace_invalido", 400)
        datos = json.loads(_desde_b64(d))
        if datos["exp"] < time.time():
            raise ErrorAplicacion("El enlace de pago venció; vuelva a intentar el pago", "enlace_vencido", 400)
        return datos

    def verificar_aviso(self, cuerpo: bytes, encabezados: dict[str, str]) -> Aviso:
        firma = encabezados.get("x-firma", "")
        if not firma or not hmac.compare_digest(firmar(cuerpo), firma):
            raise ErrorAplicacion("La firma del aviso no es válida", "firma_invalida", 400)
        try:
            datos = json.loads(cuerpo)
            return Aviso(
                id_evento=str(datos["id_evento"]),
                tipo_evento=str(datos["tipo_evento"]),
                id_pago=int(datos["id_pago"]),
                referencia=datos.get("referencia"),
                monto=Decimal(str(datos["monto"])),
                aprobado=bool(datos["aprobado"]),
                contenido=datos,
            )
        except (KeyError, ValueError, TypeError, InvalidOperation, json.JSONDecodeError) as e:
            raise ErrorAplicacion("El aviso no tiene el formato esperado", "aviso_invalido", 400) from e


_PASARELAS = {"simulada": PasarelaSimulada()}


def obtener_pasarela(nombre: str | None = None):
    pasarela = _PASARELAS.get(nombre or obtener_configuracion().pasarela)
    if pasarela is None:
        raise ErrorAplicacion("La pasarela no existe", "pasarela_no_encontrada", 404)
    return pasarela