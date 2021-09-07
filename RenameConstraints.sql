-- Rename all of the system generated constraints and their indexes
--
-- File $Id: RenameConstraints.sql 2604 2014-01-31 21:44:34Z dheltzel $
-- Modified $Author: dheltzel $ 
-- Date $Date: 2014-01-31 16:44:34 -0500 (Fri, 31 Jan 2014) $
-- Revision $Revision: 2604 $
--
SET serverout ON SIZE UNLIMITED
SET feed OFF
SET lines 150
SET pages 0
SET trimspool ON
COL spool_name FOR a40 new_value spool_name
SELECT 'RenCons_'||NAME||'_'||to_char(SYSDATE,'YYMMDDHH24MI')||'.sql' spool_name from v$database;
SPOOL &spool_name

DECLARE
  cnt PLS_INTEGER := 1;
  cur_table_name VARCHAR2(35) := 'dummy';
  indx_name VARCHAR2(35);
BEGIN
  FOR crec IN (SELECT owner, table_name, constraint_name, MIN(column_name)
   FROM dba_cons_columns WHERE (owner, table_name, constraint_name) IN
   (SELECT owner, table_name, constraint_name FROM dba_constraints WHERE (owner, table_name) IN
     (SELECT owner, table_name FROM dba_constraints WHERE owner NOT LIKE '%SYS%' AND owner NOT IN ('DBSNMP', 'XDB')
       AND constraint_type = 'U' GROUP BY owner, table_name HAVING COUNT(*) > 1) AND constraint_type = 'U' AND constraint_name LIKE 'SYS%')
   GROUP BY owner, table_name, constraint_name ORDER BY owner, table_name, MIN(column_name)) LOOP
    IF (cur_table_name != crec.table_name) THEN 
      cur_table_name := crec.table_name;
      cnt :=1;
    END IF;
    SELECT index_name INTO indx_name FROM dba_constraints WHERE owner = crec.owner AND constraint_name = crec.constraint_name;
    BEGIN
      dbms_output.put_line('ALTER TABLE ' || crec.owner || '.' || crec.table_name || ' RENAME CONSTRAINT ' || crec.constraint_name || ' TO UK'||cnt||'_' || crec.table_name || ';');
      --EXECUTE IMMEDIATE 'ALTER TABLE ' || crec.owner || '.' || crec.table_name || ' RENAME CONSTRAINT ' || crec.constraint_name || ' TO UK'||cnt||'_' || crec.table_name;
    EXCEPTION
	WHEN OTHERS THEN NULL;
    END;
    BEGIN
      dbms_output.put_line('ALTER INDEX ' || crec.owner || '.' || indx_name || ' RENAME TO UK'||cnt||'_' || crec.table_name || ';');
      --EXECUTE IMMEDIATE 'ALTER INDEX ' || crec.owner || '.' || indx_name || ' RENAME TO UK'||cnt||'_' || crec.table_name;
    EXCEPTION
	WHEN OTHERS THEN NULL;
    END;
    cnt := cnt + 1;
  END LOOP;
  -- Rename PK and UK constraints/indexes (sys generated only)
  FOR command IN (SELECT 'ALTER TABLE ' || owner || '.' || table_name || ' RENAME CONSTRAINT ' || constraint_name || ' TO PK_' || SUBSTR(table_name,1,27) constraint_ddl,
                         'ALTER INDEX ' || owner || '.' || index_name || ' RENAME TO PK_' || SUBSTR(table_name,1,27) index_ddl
                    FROM dba_constraints
                   WHERE owner NOT LIKE '%SYS%' AND owner NOT IN ('DBSNMP', 'XDB')
                     AND constraint_name LIKE 'SYS%' AND constraint_type = 'P'
                  UNION
                  SELECT 'ALTER TABLE ' || owner || '.' || table_name || ' RENAME CONSTRAINT ' || constraint_name || ' TO UK_' || SUBSTR(table_name,1,27),
                         'ALTER INDEX ' || owner || '.' || index_name || ' RENAME TO UK_' || SUBSTR(table_name,1,27)
                    FROM dba_constraints
                   WHERE owner NOT LIKE '%SYS%' AND owner NOT IN ('DBSNMP', 'XDB')
                     AND constraint_name LIKE 'SYS%' AND constraint_type = 'U') LOOP
    BEGIN
      dbms_output.put_line(command.constraint_ddl||';');
      --EXECUTE IMMEDIATE command.constraint_ddl;
    EXCEPTION
	WHEN OTHERS THEN NULL;
    END;
    BEGIN
      dbms_output.put_line(command.index_ddl||';');
      --EXECUTE IMMEDIATE command.index_ddl;
    EXCEPTION
	WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

SPOOL OFF
EXIT
