SET serverout ON
SET FEED OFF
SET PAGES 0
SET TRIMSPOOL ON
SET LINES 200
SPOOL invalid-$ORACLE_SID
SELECT object_type,owner||'.'||object_name FROM dba_objects WHERE status <> 'VALID';
DECLARE
  cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO cnt FROM dba_objects WHERE status <> 'VALID';
  IF cnt > 0 THEN
    dbms_output.put_line(cnt || ' invalid objects, compiling . . .');
    sys.utl_recomp.recomp_serial;
    SELECT COUNT(*) INTO cnt FROM dba_objects WHERE status <> 'VALID';
  END IF;
  dbms_output.put_line(cnt || ' invalid objects');
END;
/
spool off
