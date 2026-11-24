from typing import Annotated, Literal
from uuid import UUID

from fastapi import Depends, Header

TipoCliente = Literal['web', 'movil']

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

async def llave_idempotencia(
    idempotency_key: Annotated[UUID, Header(
        alias="Idempotency-Key",
        description="UUID nuevo por cada intento de operación; reenviarlo si se repite la petición",
    )],
) -> UUID:
    return idempotency_key


LlaveDep = Annotated[UUID, Depends(llave_idempotencia)]