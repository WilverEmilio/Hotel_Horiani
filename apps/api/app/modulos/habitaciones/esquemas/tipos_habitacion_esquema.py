from datetime import date

from pydantic import Field

from ....shared.esquemas.comunes import EsquemaBase, EsquemaConsulta, Monto, Texto


class CrearServicioEsquema(EsquemaBase):
    nombre: Texto
    icono: str | None = Field(None, max_length=50)


class CrearTipoEsquema(EsquemaBase):
    id_hotel: int
    nombre: Texto
    descripcion: str | None = None
    capacidad_maxima: int = Field(ge=1, le=20)
    precio_base: Monto


class ActualizarTipoEsquema(EsquemaBase):
    nombre: Texto
    descripcion: str | None = None
    capacidad_maxima: int = Field(ge=1, le=20)
    activo: bool = True


class PrecioBaseEsquema(EsquemaBase):
    precio_base: Monto


class ServiciosTipoEsquema(EsquemaBase):
    ids_servicio: list[int] = Field(default_factory=list, description="Lista completa; reemplaza la actual")


class CrearTarifaEsquema(EsquemaBase):
    nombre: Texto
    fecha_inicio: date = Field(description="Primera noche con la tarifa")
    fecha_fin: date = Field(description="Última noche con la tarifa (incluida)")
    precio_noche: Monto


class TarifasConsulta(EsquemaConsulta):
    incluir_inactivas: bool = False


class ImagenTipoEsquema(EsquemaBase):
    url: str = Field(min_length=1, max_length=500)
    texto_alternativo: Texto