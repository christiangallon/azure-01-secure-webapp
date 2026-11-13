#!/bin/bash
if ! odbcinst -q -d | grep -q "ODBC Driver 18"; then
  curl -sSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add - 
  curl -sSL https://packages.microsoft.com/config/debian/12/prod.list > /etc/apt/sources.list.d/mssql-release.list
  apt-get update && ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev
fi
gunicorn -w 2 -k uvicorn.workers.UvicornWorker app.main:app --bind 0.0.0.0:8000
