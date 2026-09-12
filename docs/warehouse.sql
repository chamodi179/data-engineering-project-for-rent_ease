-- One database for the whole RentEase analytics platform
CREATE DATABASE RENTEASE_DWH;

CREATE SCHEMA RENTEASE_DWH.BRONZE;   -- raw, 1:1 with MariaDB tables
CREATE SCHEMA RENTEASE_DWH.SILVER;   -- cleaned, typed, deduped, conformed
CREATE SCHEMA RENTEASE_DWH.GOLD;     -- star schema: facts + dims for BI

-- Separate compute warehouse (this is the "engine", billed separately)
CREATE WAREHOUSE RENTEASE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60          -- suspends after 60s idle, saves credits
  AUTO_RESUME = TRUE;

-- according to the current system (local mysql database) 
-- wanna enable cdc and read data from cdc and write to
--  the s3 (minio) -> ware house (spark)