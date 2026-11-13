#!/usr/bin/env bash
# Post-deploy: load the schema and create the contained database user for the
# web app's managed identity with least privilege (db_datareader + db_datawriter,
# no db_owner, no DDL). azurerm cannot do this: it is a T-SQL operation inside
# the database, not an ARM resource.
#
# Must run as the Entra SQL admin (the identity that ran Terraform, or a member of
# the admin group). Uses go-sqlcmd with -G (Entra auth; picks up `az login` locally
# or the azure/login OIDC session in GitHub Actions).
#
#   cd infra && ../scripts/grant-sql-access.sh            # reads terraform outputs
#   SQL_SERVER=... SQL_DB=... APP_NAME=... ./scripts/grant-sql-access.sh
#
# APP_CLIENT_ID (optional): the managed identity's client/application ID. When set,
# the user is created WITH SID (no Graph lookup by the SQL server needed). This is
# required when the executing admin is a SERVICE PRINCIPAL, because
# "FROM EXTERNAL PROVIDER" then needs the SQL server identity to have Directory
# Readers, which a sandbox normally cannot grant.
set -euo pipefail

tf_out() { terraform output -raw "$1" 2>/dev/null || true; }
SQL_SERVER="${SQL_SERVER:-$(tf_out sql_server_fqdn)}"
SQL_DB="${SQL_DB:-$(tf_out sql_database_name)}"
APP_NAME="${APP_NAME:-$(tf_out web_app_name)}"
SCHEMA_FILE="${SCHEMA_FILE:-$(dirname "$0")/../sql/schema.sql}"
: "${SQL_SERVER:?SQL_SERVER not set and no terraform output}"
: "${SQL_DB:?SQL_DB not set}"
: "${APP_NAME:?APP_NAME not set}"

# Simple guard against T-SQL injection through the name.
[[ "$APP_NAME" =~ ^[A-Za-z0-9-]+$ ]] || { echo "Invalid APP_NAME"; exit 1; }

run_sql() { sqlcmd -S "$SQL_SERVER" -d "$SQL_DB" -G -b "$@"; }

echo "1/3 Loading schema ($SCHEMA_FILE)"
run_sql -i "$SCHEMA_FILE"

echo "2/3 Creating contained user [$APP_NAME]"
if [ -n "${APP_CLIENT_ID:-}" ]; then
  [[ "$APP_CLIENT_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "Invalid APP_CLIENT_ID"; exit 1; }
  run_sql -Q "
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$APP_NAME')
BEGIN
  DECLARE @sid NVARCHAR(100) = CONVERT(NVARCHAR(100), CONVERT(VARBINARY(16), CAST('$APP_CLIENT_ID' AS UNIQUEIDENTIFIER)), 1);
  EXEC (N'CREATE USER [$APP_NAME] WITH SID = ' + @sid + N', TYPE = E;');
END"
else
  run_sql -Q "
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$APP_NAME')
  CREATE USER [$APP_NAME] FROM EXTERNAL PROVIDER;"
fi

echo "3/3 Granting db_datareader + db_datawriter"
run_sql -Q "
ALTER ROLE db_datareader ADD MEMBER [$APP_NAME];
ALTER ROLE db_datawriter ADD MEMBER [$APP_NAME];
SELECT dp.name AS member, r.name AS role
FROM sys.database_role_members m
JOIN sys.database_principals r  ON r.principal_id  = m.role_principal_id
JOIN sys.database_principals dp ON dp.principal_id = m.member_principal_id
WHERE dp.name = N'$APP_NAME';"

echo "Done."
