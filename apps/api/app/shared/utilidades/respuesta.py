from typing import Any

from .mapeo import a_camel


def respuesta(mensaje: str,
              datos: Any = None,
              conservar: frozenset[str] = frozenset()) ->  dict:
    return {
        'mensaje': mensaje,
        'datos': a_camel(datos, conservar)
    }
    
def paginar(filas: list[dict],
            pagina: int,
            tamano_pagina: int) -> dict:
    total = int (filas[0]['total_registros']) if filas else 0
    return{
        "items": [{k: v for k, v in f.items() if k != "total_registros"} for f in filas],
        'pagina': pagina,
        'tamano_pagina': tamano_pagina,
        'total_registros': total
    }