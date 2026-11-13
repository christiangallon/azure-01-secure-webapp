import os, struct, pyodbc
from azure.identity import DefaultAzureCredential

def get_conn():
    server, db = os.environ["SQL_SERVER"], os.environ["SQL_DB"]
    cs = (f"Driver={{ODBC Driver 18 for SQL Server}};Server=tcp:{server},1433;"
          f"Database={db};Encrypt=yes;")
    tok = DefaultAzureCredential().get_token("https://database.windows.net/.default").token.encode("utf-16-le")
    return pyodbc.connect(cs, attrs_before={1256: struct.pack(f"<I{len(tok)}s", len(tok), tok)})
