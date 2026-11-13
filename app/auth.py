import base64, json, os
from fastapi import Depends, Header, HTTPException

LOCAL_DEV = os.getenv("LOCAL_DEV") == "1"
if LOCAL_DEV and os.getenv("WEBSITE_SITE_NAME"):
    raise RuntimeError("LOCAL_DEV must never be enabled in Azure")

ROLE_TYPES = ("roles", "http://schemas.microsoft.com/ws/2008/06/identity/claims/role")

def current_user(x_ms_client_principal: str | None = Header(default=None),
                 x_ms_client_principal_name: str | None = Header(default=None)):
    if LOCAL_DEV:
        return {"name": "dev@local", "roles": ["Editor"]}
    if not x_ms_client_principal:
        raise HTTPException(401, "Not authenticated")
    data = json.loads(base64.b64decode(x_ms_client_principal))
    roles = [c["val"] for c in data.get("claims", []) if c["typ"] in ROLE_TYPES]
    return {"name": x_ms_client_principal_name, "roles": roles}

def require(*allowed):
    def dep(user=Depends(current_user)):
        if not set(allowed) & set(user["roles"]):
            raise HTTPException(403, "Authenticated but not authorized")
        return user
    return dep
