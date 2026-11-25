from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol


@dataclass(frozen=True)
class Cobro: 
    url_pago: str
    
@dataclass(frozen=True)
class Aviso:
    id_evento: str
    tipo_evento: str
    id_pago: int
    referencia: str | None
    monto: Decimal
    aprobado: bool
    contenido: dict
    
class Pasarela(Protocol):
    nombre: str 
    
    def crear_cobro(
        self, 
        id_pago: int,
        id_reservacion: int,
        monto: Decimal
    ) -> Cobro:
        '''Prerata el cobro y devuelve la URL a la uqe se envia al cliente'''
        ...
        
    def verifivar_aviso(
        self,
        cuepo: bytes,
        encabezados: dict[str, str]
    ) -> Aviso:
        '''Verifica la firma del aviso y lo traduce: Lanza ErroAplicacion(400) si no es valida'''
        ...