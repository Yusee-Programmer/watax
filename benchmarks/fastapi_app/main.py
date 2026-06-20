from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

app = FastAPI()


@app.get("/", response_class=PlainTextResponse)
def root():
    return "Hello, World!"


@app.get("/json")
def json_endpoint():
    return {"message": "Hello, World!", "id": 1, "ok": True}


@app.get("/greet/{name}")
def greet(name: str):
    # Path-parameter route: GET /greet/:name -> {"hello": <name>}
    return {"hello": name}
