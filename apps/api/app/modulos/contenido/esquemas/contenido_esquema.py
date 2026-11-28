from typing import Any, Literal

from pydantic import Field

from ....shared.esquemas.comunes import EsquemaBase, EsquemaConsulta


class GuardarContenidoEsquema(EsquemaBase):
    id_hotel: int | None = Field(None, description="Vacío = contenido general de la cadena")
    pagina: str = Field(min_length=1, max_length=60, description="ej. inicio, habitaciones, sobre-nosotros")
    seccion: str = Field(min_length=1, max_length=60)
    clave: str = Field(min_length=1, max_length=60)
    tipo: Literal["texto", "texto_largo", "imagen", "lista"]
    valor: Any = Field(description="texto: string; imagen: {url, alt}; lista: arreglo. Se guarda tal cual")
    orden: int = Field(0, ge=0)
    publicado: bool = True


class PublicadoEsquema(EsquemaBase):
    publicado: bool


class ContenidoConsulta(EsquemaConsulta):
    id_hotel: int | None = None
    pagina: str | None = None