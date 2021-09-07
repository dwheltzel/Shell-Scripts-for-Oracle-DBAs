set pages 0
SET trimspool ON
COL spool_name FOR a40 new_value spool_name
SELECT 'DeployUtils_'||db_unique_name||'_'||to_char(SYSDATE,'YYMMDDHH24MI')||'.sql' spool_name from v$database;
SPOOL &spool_name

SELECT text FROM dba_source WHERE owner = 'DBADMIN' AND NAME = 'DEPLOY_UTILS' AND TYPE = 'PACKAGE BODY' AND text LIKE '%-- Revision%';
SELECT 'GET_CURRENT_REVISION:'||COUNT(*) "EXISTS" FROM dba_procedures WHERE owner = 'DBADMIN' AND object_name = 'DEPLOY_UTILS' AND procedure_name = 'DEPLOY_NEW_SEQUENCE_CUST';
exit
