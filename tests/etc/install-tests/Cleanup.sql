if OBJECT_ID('dbo.a') IS NOT NULL
	drop table a
if OBJECT_ID('dbo.b') IS NOT NULL
	drop table b
if OBJECT_ID('dbo.c') IS NOT NULL
	drop table c
if OBJECT_ID('dbo.d') IS NOT NULL
	drop table d
if OBJECT_ID('dbo.testdeploymenthistory') IS NOT NULL
	EXEC ('TRUNCATE TABLE dbo.testdeploymenthistory')
if OBJECT_ID('dbo.testdeploymenthistory') IS NOT NULL
	drop table dbo.testdeploymenthistory