@@partition_&&1-setup.sql

SET SERVEROUT ON SIZE UNLIMITED
SET TIME ON 
SET TIMI ON
SET LINES 150
SET PAGES 1000

SPOOL partition_&&V_TABLE-abort.lst

prompt Aborting the redefinition
BEGIN
  dbms_redefinition.abort_redef_table('&&V_OWNER', '&&V_TABLE', '&&V_PART_TABLE');
END;
/

prompt dropping the table
DROP TABLE &&V_OWNER..&&V_PART_TABLE;

SPOOL OFF
