/*
Script Purpose:
    This scripts creates a new database names 'DataWarehouse' after checking if it already exists.
    If the database exists, it is fropped and recreated. Additionally, the scripts sets up thee schemas 
    within the database: 'bronze', 'silver', and 'gold'.
*/

USE master;
GO

--- Drop and recreate the 'DataWarehouse' database
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouse')
BEGIN
    ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DataWarehouse;
END;
GO

--- Create the 'DataWarehouse' database
CREATE DATABASE DataWarehouse;
GO

USE DataWarehouse;
GO

--- Create Schemas
CREATE SCHEMA bronze;
GO
  
CREATE SCHEMA silver;
GO
  
CREATE SCHEMA gold;
GO
