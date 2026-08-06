from fastapi import FastAPI

app = FastAPI(title="HOTEL HORIANI API")

@app.get("/health")
def health():
 return {"status": "ok"}
