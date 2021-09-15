@@partition_&&1-setup.sql

SET SERVEROUT ON SIZE UNLIMITED
SET TIME ON 
SET TIMI ON
SET LINES 150
SET PAGES 1000

SPOOL partition_&&V_TABLE-2.lst

-- Re-sync the data to make finalize faster
BEGIN
  dbms_redefinition.sync_interim_table('&&V_OWNER', '&&V_TABLE', '&&V_PART_TABLE');
END;
/

-- Any locks occur here, so monitor the db closely
BEGIN
  dbms_redefinition.finish_redef_table('&&V_OWNER', '&&V_TABLE', '&&V_PART_TABLE');
END;
/

-- Final checks to see that the records are all there. Differences could be attributed to DML since the finish_redef_table procedure was run
SELECT COUNT(*) FROM &&V_OWNER..&&V_TABLE;
SELECT COUNT(*) FROM &&V_OWNER..&&V_PART_TABLE;
SELECT 'Total Data Segments', ROUND(SUM(bytes)/1024/1024,0) MB, count(*) segments
  FROM dba_segments WHERE owner = '&&V_OWNER' AND segment_name = '&&V_TABLE'
UNION
SELECT 'Total Index Segments', ROUND(SUM(bytes)/1024/1024,0) MB, count(*) segments
  FROM dba_segments WHERE (owner,segment_name) IN (SELECT owner,index_name FROM dba_indexes WHERE table_owner = '&&V_OWNER' AND table_name = '&&V_TABLE')
UNION
SELECT 'Total LOB Segments', ROUND(SUM(bytes)/1024/1024,0) MB, count(*) segments
  FROM dba_segments WHERE (owner,segment_name) IN (SELECT owner,segment_name FROM dba_lobs WHERE owner = '&&V_OWNER' AND table_name = '&&V_TABLE');

exec DBMS_STATS.GATHER_TABLE_STATS('&&V_OWNER','"&&V_TABLE"');

SPOOL OFF
