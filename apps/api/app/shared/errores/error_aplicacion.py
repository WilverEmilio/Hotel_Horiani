class ErrorAplicacion(Exception):
    def __ini__(self, 
                mensaje: str, 
                codigo: str, 
                estado_http: int,
                detalles: list[dict] | None = None, 
                encabezados: dict | None = None
                ):
        super().__init__(mensaje)
        self.mensaje = mensaje
        self.codigo = codigo
        self.estado_http = estado_http
        self.detalles = detalles
        self.encabezados = encabezados