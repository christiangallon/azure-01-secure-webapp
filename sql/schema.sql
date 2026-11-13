-- Idempotent so the pipeline can re-run it safely (v1 used a plain CREATE TABLE).
IF OBJECT_ID(N'dbo.Items', N'U') IS NULL
CREATE TABLE dbo.Items (
  Id INT IDENTITY PRIMARY KEY,
  Title NVARCHAR(200) NOT NULL,
  CreatedBy NVARCHAR(256) NOT NULL,
  CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
