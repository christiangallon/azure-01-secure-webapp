import os
from fastapi import FastAPI, Depends
from pydantic import BaseModel
from .auth import require
from .db import get_conn

if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor()

app = FastAPI(title="secure-webapp")

class ItemIn(BaseModel):
    title: str

@app.get("/health")
def health(): return {"status": "ok"}

@app.get("/me")
def me(user=Depends(require("Reader", "Editor"))): return user

@app.get("/items")
def list_items(user=Depends(require("Reader", "Editor"))):
    with get_conn() as c:
        rows = c.cursor().execute("SELECT Id,Title,CreatedBy FROM dbo.Items").fetchall()
    return [dict(id=r[0], title=r[1], created_by=r[2]) for r in rows]

@app.post("/items", status_code=201)
def add_item(item: ItemIn, user=Depends(require("Editor"))):
    with get_conn() as c:
        c.cursor().execute("INSERT dbo.Items(Title,CreatedBy) VALUES(?,?)", item.title, user["name"])
        c.commit()
    return {"ok": True}

@app.get("/boom")
def boom(user=Depends(require("Editor"))): raise RuntimeError("intentional failure")

@app.get("/config-check")
def config_check(user=Depends(require("Editor"))):
    v = os.getenv("API_KEY")
    return {"api_key_loaded": bool(v), "length": len(v) if v else 0}
