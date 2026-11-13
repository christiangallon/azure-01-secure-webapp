import base64, json, os
os.environ["LOCAL_DEV"] = "1"
from fastapi.testclient import TestClient
from app.main import app
import app.auth as auth
c = TestClient(app)

def principal(roles):
    claims = [{"typ": "roles", "val": r} for r in roles]
    return base64.b64encode(json.dumps({"claims": claims}).encode()).decode()

def test_health(): assert c.get("/health").json() == {"status": "ok"}
def test_local_me(): assert c.get("/me").json()["roles"] == ["Editor"]

def test_401_without_principal(monkeypatch):
    monkeypatch.setattr(auth, "LOCAL_DEV", False)
    assert c.get("/me").status_code == 401

def test_403_without_role(monkeypatch):
    monkeypatch.setattr(auth, "LOCAL_DEV", False)
    assert c.get("/me", headers={"X-MS-CLIENT-PRINCIPAL": principal([])}).status_code == 403

def test_200_with_role(monkeypatch):
    monkeypatch.setattr(auth, "LOCAL_DEV", False)
    assert c.get("/me", headers={"X-MS-CLIENT-PRINCIPAL": principal(["Reader"]), "X-MS-CLIENT-PRINCIPAL-NAME": "a@b.c"}).status_code == 200
