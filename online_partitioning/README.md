These scripts can be used to facilitate partitioning of existing tables using Oracle's Online Table Redefinition. 

partition_CUST-1.sql - Rename this, changing CUST to the table name (without schema)

partition_CUST-local.sql - Create this as an empty file, changing CUST to the table name (without schema)

partition_CUST-setup.sql - Rename this, changing CUST to the table name (without schema)

partition-2.sql - Used to run the second stage, with the table name passed as the only parameter

partition-abort.sql - Used to abort the redefinition and drop the interim table, with the table name passed as the only parameter

The first 3 files are customized for each table, edit them to have the correct information.
