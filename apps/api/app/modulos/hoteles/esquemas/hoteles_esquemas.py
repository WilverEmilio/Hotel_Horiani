from datetime import time
from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import Correo, EsquemaBase, Porcentaje, Texto

SeccionImagen = Literal["carrusel", "galeria"]


class CrearHotelEsquema(EsquemaBase):
    nombre: Texto
    slug: str = Field(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$", max_length=80,
                      description="Para la URL, ej. horiani-quetzaltenango")
    direccion: Texto
    ciudad: Texto
    telefono: str | None = None
    correo: Correo | None = None


class ActualizarHotelEsquema(EsquemaBase):
    nombre: Texto
    direccion: Texto
    ciudad: Texto
    telefono: str | None = None
    correo: Correo | None = None
    activo: bool = True


class ConfiguracionHotelEsquema(EsquemaBase):
    hora_checkout: time
    porcentaje_anticipo: Porcentaje = Field(gt=0)
    minutos_bloqueo_pago: int = Field(gt=0, le=1440)
    horas_limite_cancelacion: int | None = Field(None, ge=0, description="null = política aún no definida")
    porcentaje_reembolso: Porcentaje | None = None
    no_presentacion_pierde_anticipo: bool | None = None


class ImagenHotelEsquema(EsquemaBase):
    url: str = Field(min_length=1, max_length=500, description="https://... o ruta que empiece con /")
    texto_alternativo: Texto
    seccion: SeccionImagen = "galeria"


class OrdenImagenesHotelEsquema(EsquemaBase):
    seccion: SeccionImagen
    ids: list[int] = Field(min_length=1, description="Ids de las imágenes en el orden deseado")