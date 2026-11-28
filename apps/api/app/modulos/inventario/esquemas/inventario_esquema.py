from datetime import date
from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import (
    Cantidad,
    CantidadCero,
    ConsultaPaginada,
    Direccion,
    EsquemaBase,
    Texto,
    TextoCorto,
    TextoOpcional,
)

Clase = Literal['insumo', 'blanco']
Ubicacion = Literal['bodega', 'habitaciones', 'lavanderia']
TipoMovimiento = Literal['entrada', 'salida', 'ajuste_positivo', 'ajuste_negativo','traslado', 'baja']

class CrearCategoriaEsquemaU(EsquemaBase):
    nombre: Texto
    
class CrearArticuloEsquema(EsquemaBase):
    id_hotel: int
    id_categoria_articulo: int
    nombre: Texto
    clase: Clase
    unidad_medida: Texto = Field(
        description = 'unidad, rollo, galon, pieza...'
    )
    existencia_minima: CantidadCero = 0
    
class ActualizarArticuloEsquema(EsquemaBase):
    id_categoria_articulo: int
    nombre: Texto
    unidad_medida: Texto
    existencia_minima: CantidadCero
    activo: bool = True


class EntradaEsquema(EsquemaBase):
    cantidad: Cantidad
    motivo: TextoOpcional = None


class ConteoEsquema(EsquemaBase):
    ubicacion: Ubicacion
    cantidad_contada: CantidadCero          
    motivo: TextoCorto                      


class ConsumoEsquema(EsquemaBase):
    cantidad: Cantidad
    id_habitacion: int | None = None
    motivo: TextoOpcional = None


class BajaEsquema(EsquemaBase):
    ubicacion: Ubicacion
    cantidad: Cantidad
    motivo: TextoCorto


class ItemEsquema(EsquemaBase):
    id_articulo: int
    cantidad: Cantidad


class BlancosEsquema(EsquemaBase):
    items: list[ItemEsquema] = Field(min_length=1)


class ExistenciasConsulta(ConsultaPaginada):
    id_hotel: int
    clase: Clase | None = None
    busqueda: str | None = Field(None, max_length=100)
    solo_bajo_minimo: bool = False
    incluir_inactivos: bool = False
    ordenar_por: Literal["nombre", "bodega", "categoria"] = "nombre"
    direccion: Direccion = "asc"


class MovimientosConsulta(ConsultaPaginada):
    id_hotel: int
    id_articulo: int | None = None
    tipo: TipoMovimiento | None = None
    fecha_desde: date | None = None
    fecha_hasta: date | None = None