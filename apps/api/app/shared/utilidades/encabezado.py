from typing import Annotated, Literal
from fastapi import Depends, Header

TipoCliente = Literal['web', 'mobil']

async def tipo_cliente(
    x_cliente: Annotated[
        TipoCliente,
        Header(
            description = "'movil' para la app; 'web' por defecto"
        )
    ] = 'web',
) -> TipoCliente:
    return x_cliente

ClienteDep = Annotated[TipoCliente,Depends(tipo_cliente)]