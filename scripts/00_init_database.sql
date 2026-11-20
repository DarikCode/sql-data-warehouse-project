/*
=============================================================
 Create the database and schemas
=============================================================
 Purpose:
   Creates a fresh 'datawarehouse' database with one schema
   per layer of the medallion architecture:
     bronze - raw data, loaded as-is from the source CSVs
     silver - cleaned and standardized data
     gold   - business-ready star schema for reporting
   plus one for the pipeline itself:
     etl    - log of every pipeline run and step

 WARNING:
   This drops the 'datawarehouse' database if it exists and
   deletes ALL data in it. Run it only to start from scratch.

 How to run (psql, connected to the default 'postgres' database):
   psql -U postgres -h localhost -f scripts/00_init_database.sql
=============================================================
*/

-- PostgreSQL cannot drop the database you are connected to,
-- which is why this script starts from the 'postgres' database.
-- WITH (FORCE) disconnects any other open sessions first.
DROP DATABASE IF EXISTS datawarehouse WITH (FORCE);
CREATE DATABASE datawarehouse;

-- psql command: switch the connection to the new database.
-- (PostgreSQL has no USE statement like SQL Server.)
\connect datawarehouse

CREATE SCHEMA bronze;
CREATE SCHEMA silver;
CREATE SCHEMA gold;
CREATE SCHEMA etl;   -- pipeline run log, see scripts/etl/ddl_etl.sql
