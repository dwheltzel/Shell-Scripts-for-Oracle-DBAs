# Create a health check report
#
CRED=${CRED:-/}
if [ -r SetEnv.sh ] ; then
. ./SetEnv.sh
fi

usage() {
      echo "Usage: $0 [-s] [-d database name] [-m email address]"
      echo "  -s - run space usage report"
      echo "  -d database name - defaults to $ORACLE_SID"
      echo "  -m email address - send the report to this address"
      exit 1
}

space_usage() {
export REPORT_NAME=SpaceUsageReport_${DB_NAME}-`date "+%y%m%d%H%M"`.lst
export REPORT_TITLE="Space Usage Report for ${DB_NAME}"

sqlplus -s ${CRED} as sysdba <<!
SET PAGES 0
SET TRIMSPOOL ON
COL tablespace FOR a20
COL realsize FOR 99,999.9
COL used FOR 99,999.9
COL files FOR 999
COL free FOR 99,999.9
COL "% FREE" FOR 999.9
COL spool_name FOR a40 new_value spool_name
SELECT 'FreeSpace_'||NAME||'_'||to_char(SYSDATE,'YYMMDDHH24MI')||'.sql' spool_name from v$database;
spool ${REPORT_NAME}
prompt ${REPORT_TITLE}
SET PAGES 200

SELECT a.tablespace_name tablespace,round(a.realsize_bytes/1024/1024/1024,1) realsize,round(b.tot_bytes/1024/1024/1024,1) used,
  ROUND((a.realsize_bytes-b.tot_bytes)/1024/1024/1024,1) free,
  ROUND((a.realsize_bytes-b.tot_bytes)/a.realsize_bytes*100,1) "% FREE",storage,files FROM
-- show the true size that a tablespace can expand to
(SELECT tablespace_name,SUM(realsize) realsize_bytes,MAX(storage) storage,count(*) files FROM
(SELECT tablespace_name,CASE WHEN autoextensible = 'YES' THEN maxbytes ELSE bytes END realsize,
decode(substr(file_name,1,4),'/u03','ZFS','EXA') storage
  FROM dba_data_files) GROUP BY tablespace_name) a
JOIN
-- show the current space in use by all extents
(SELECT tablespace_name,SUM(bytes) tot_bytes
  FROM dba_extents
 GROUP BY tablespace_name) b
ON (a.tablespace_name = b.tablespace_name)
ORDER BY 5;

prompt Empty Tablespaces:
SELECT tablespace_name,decode(substr(file_name,1,4),'/u03','ZFS','EXA') storage,count(*) files FROM dba_data_files
 WHERE tablespace_name NOT IN (SELECT DISTINCT tablespace_name FROM dba_segments)
 GROUP BY tablespace_name,decode(substr(file_name,1,4),'/u03','ZFS','EXA') ORDER BY 1,2;

SPOOL OFF
exit
!
}

# Handle parameters
while getopts ":d:m:" opt; do
  case $opt in
    s)
      space_usage
      ;;
    d)
      export TWO_TASK=$OPTARG
      DB_NAME=$OPTARG
      ;;
    m)
      export MAILTO=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
    :)
      if [ "${OPTARG}" = 'm' ] ; then
        export MAILTO=dba@example.com
      else
        echo "Option -$OPTARG requires an argument." >&2
        usage
      fi
      ;;
  esac
done

DB_NAME=${DB_NAME:-${ORACLE_SID}}

export REPORT_NAME=GeneralHealthReport_${DB_NAME}-`date "+%y%m%d%H%M"`.lst
export REPORT_TITLE="Health Report for ${DB_NAME}"

sqlplus -s ${CRED} as sysdba <<!
set ver off
set lines 120
set pages 500
set trimspool on
col service for a9
col edition for a8
col edition_name for a16
col osuser for a15
col username for a15
col trig_name for a50
col tab_name for a40
col status for a10
col valid for 99,999
col invalid for 99,999
col synonyms for 99,999
col total for 99,999
spool ${REPORT_NAME}
prompt ${REPORT_TITLE}

set head off
set feed off
select 'Report time: '||to_char(sysdate, 'Mon DD, YYYY HH:MI AM') from dual;
prompt
prompt ============ Status Info =========================================================
set head off
prompt Check for restore points
select 'Restore point active: '||name||' at '||time from v\$restore_point;
prompt
prompt Check ACL's
SELECT decode(COUNT(*), 1, 'ACL OK', 'ACL Error') FROM sys.dba_network_acls WHERE host = '*';
SELECT 'HTTP Port in use: '||xdb.dbms_xdb.gethttpport FROM dual;
--SELECT CASE WHEN xdb.dbms_xdb.gethttpport = 8080 THEN ' ' ELSE 'exec dbms_xdb.sethttpport(''8080'')' END http_port_check FROM dual;
prompt
prompt Check for Registry problems
SELECT status||' '||comp_name FROM dba_registry WHERE status <> 'VALID';
set head off
prompt
prompt ============ Structural Problems ==================================================
SELECT 'Index owner mismatch: '||table_owner||'.'||table_name||'   Index: '||owner||'.'||index_name FROM dba_indexes WHERE owner <> table_owner ORDER BY 1;
SELECT 'LONG data type: '||owner||'.'||table_name FROM dba_tab_cols c WHERE DATA_TYPE = 'LONG' AND owner NOT LIKE 'APEX%'
 AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA');
prompt
prompt Invalid indexes
select 'alter index ' || owner || '.' || index_name || ' rebuild nologging online;' from dba_indexes where status = 'UNUSABLE'
union
select 'alter index ' || index_owner || '.' || index_name || ' rebuild partition ' || partition_name || ' nologging online' || ';' from dba_ind_partitions where status = 'UNUSABLE';
prompt
prompt Nonunique indexes supporting Unique keys
set lines 800
col table for a45
col constraint_name for a30
col index for a45
SELECT c.constraint_type,c.owner||'.'||c.table_name "TABLE",c.constraint_name,c.index_owner||'.'||c.index_name "INDEX",i.uniqueness
  FROM dba_constraints c JOIN dba_indexes i ON (i.owner = c.index_owner AND i.index_name = c.index_name)
 WHERE c.constraint_type IN ('P', 'U') AND i.uniqueness = 'NONUNIQUE' ORDER BY 2,1;
prompt
prompt Chained synonyms
SELECT * FROM dba_synonyms WHERE (table_owner,table_name) IN (SELECT owner,synonym_name FROM dba_synonyms);
prompt Compile invalid synonyms
select 'alter synonym '||owner||'.'||object_name||' compile;' from dba_objects where status='INVALID' and object_type='SYNONYM' and owner<>'PUBLIC'
union
select 'alter public synonym '||object_name||' compile;' from dba_objects where status='INVALID' and object_type='SYNONYM' and owner='PUBLIC';
prompt Remove orphaned synonyms
SELECT 'drop synonym '||s.owner||'.'||s.synonym_name||';' FROM dba_synonyms s, dba_tab_privs t
 WHERE s.table_owner=t.owner(+) AND s.table_name=t.table_name(+) AND t.table_name IS NULL
   AND s.owner NOT IN ('PUBLIC','APEX_LISTENER','SYS','SYSTEM') ORDER BY 1;
prompt
prompt Find any needed grants to insert into tables with sequences in the default values
set serverout on size unlimited
DECLARE
  c_sequence VARCHAR2(300);
  c_schema   VARCHAR2(30) := '';
BEGIN
  FOR r IN (SELECT owner, table_name, data_default FROM dba_tab_cols WHERE data_default IS NOT NULL)
  LOOP
    c_sequence := TRIM(lower(substr(r.data_default,0,300)));
    IF (c_sequence LIKE '%nextval%') THEN
      c_sequence := substr(c_sequence, 1, instr(c_sequence,'.',-1,1) - 1);
      IF (instr(c_sequence, '.') > 0) THEN
        c_schema   := replace(upper(substr(c_sequence,1,instr(c_sequence,'.',1,1) - 1)),'"','');
        c_sequence := replace(upper(substr(c_sequence, instr(c_sequence, '.',1,1) + 1)),'"','');
      END IF;
      IF (c_schema = '') THEN
        c_schema := 'unknown';
      END IF;
      FOR g_rec IN (SELECT grantee FROM dba_tab_privs WHERE PRIVILEGE = 'INSERT' AND owner = r.owner AND table_name = r.table_name
                    MINUS
                    SELECT grantee FROM dba_tab_privs WHERE PRIVILEGE = 'SELECT' AND owner = c_schema AND table_name = c_sequence)
      LOOP
        dbms_output.put_line('grant select on ' || c_schema || '.' ||
                             c_sequence || ' to ' || g_rec.grantee || ';');
      END LOOP;
    END IF;
  END LOOP;
END;
/
prompt
prompt Find any needed grants that are missing the grant option
SELECT DISTINCT 'grant select on '||referenced_owner||'.'||referenced_name||' to '||owner||' with grant option;'
  FROM dba_dependencies d WHERE referenced_owner <> owner AND TYPE = 'VIEW'
   AND referenced_type = 'TABLE' AND owner NOT LIKE 'APEX%'
   AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA')
   -- filter out any views that have not been granted to anyone
   AND (d.owner, d.name) IN (SELECT p.owner, p.table_name FROM dba_tab_privs p
       JOIN dba_objects o ON (o.owner = p.owner AND o.object_name = p.table_name AND o.object_type = 'VIEW') WHERE p.privilege = 'SELECT')
MINUS
SELECT DISTINCT 'grant select on '||owner||'.'||table_name||' to '||grantee||' with grant option;' FROM dba_tab_privs WHERE privilege = 'SELECT' AND grantable = 'YES';
prompt
prompt Find excessive grants 
SELECT 'revoke '||privilege||' on '||owner||'."'||table_name||'" from '||grantee||';' cmd
  FROM dba_tab_privs p JOIN dba_users u ON (u.username=p.owner)
 WHERE grantee <> owner AND grantee NOT LIKE 'APEX%'
   AND grantee not in (select owner from dba_logstdby_skip where statement_opt = 'INTERNAL SCHEMA')
   and owner not in (select owner from dba_logstdby_skip where statement_opt = 'INTERNAL SCHEMA')
   and privilege in ('ON COMMIT REFRESH','FLASHBACK','QUERY REWRITE','INDEX','DEBUG','ALTER') ORDER BY grantee,owner,table_name,privilege;
prompt
prompt ============ Performance ====================================================
prompt Checking for tables that need to be analyzed
SELECT 'exec DBMS_STATS.GATHER_TABLE_STATS('''||t.owner||''','''||t.table_name||''');' FROM dba_tables t
 JOIN dba_tab_statistics s ON (s.OWNER = t.OWNER AND s.TABLE_NAME = t.TABLE_NAME)
 WHERE t.owner NOT LIKE '%SYS%' AND t.owner NOT IN ('XDB') AND t.temporary = 'N' AND t.secondary = 'N' AND t.segment_created = 'YES'
 AND (t.owner,t.table_name) NOT IN (SELECT owner, table_name FROM dba_external_tables)
 AND s.stattype_locked IS NULL AND (t.last_analyzed < SYSDATE -  30 OR t.last_analyzed IS NULL) AND t.table_name NOT LIKE 'SYS%'
 ORDER BY t.num_rows;
prompt
-- prompt ============ GoldenGate checks =========================================
-- SELECT DECODE(COUNT(*),1,'GG - Sequence modulo values OK','GG - Issue with sequences - check modulo values') FROM (
-- SELECT increment_by,MOD(last_number, 10),COUNT(*) FROM dba_sequences
-- WHERE sequence_owner IN ('SCOTT')
-- GROUP BY increment_by,MOD(last_number, 10));
-- prompt Find any identity columns (not supported by GoldenGate)
-- SELECT 'create sequence '||ic.owner||'.'||ic.table_name||'_SEQ start with '||to_char(s.last_number +1)||';'||CHR(10)||
-- 'alter table '||ic.owner||'.'||ic.table_name||' modify '||ic.column_name||' drop identity;'||CHR(10)||
-- 'alter table '||ic.owner||'.'||ic.table_name||' modify '||ic.column_name||' default on null '||ic.owner||'.'||ic.table_name||'_SEQ.nextval;' fix_cmd
-- FROM dba_tab_identity_cols ic JOIN dba_sequences s ON (ic.owner = s.sequence_owner AND ic.sequence_name = s.sequence_name)
-- ORDER BY 1;
prompt
prompt ============ Leftover Datapump Jobs =========================================
SELECT owner_name,job_name,rtrim(operation) "OPERATION",rtrim(job_mode) "JOB_MODE",state,attached_sessions 
 FROM dba_datapump_jobs WHERE state = 'NOT RUNNING' ORDER BY 1, 2;
SELECT 'drop table '||o.owner||'.'||object_name||';' FROM dba_objects o, dba_datapump_jobs j
 WHERE o.owner = j.owner_name AND o.object_name = j.job_name AND state = 'NOT RUNNING';
prompt
prompt ============ Data Dictionary ================================================
set pages 0
select 'alter session set edition=' || edition_name || ';' || chr(10) || decode(object_type, 'PACKAGE BODY', 'alter package ' || owner || '.' || object_name || ' compile body;', 'alter ' || object_type || ' ' || owner || '.' || object_name || ' compile;') cmd
  from dba_objects_ae where object_id in (select do.obj# d_obj from sys.obj$ do, sys.dependency$ d, sys.obj$ po
  where p_obj# = po.obj#(+) and d_obj# = do.obj# and do.status = 1 /*dependent is valid*/ and po.status = 1 /*parent is valid*/ and po.stime != p_timestamp /*parent timestamp not match*/ ) and edition_name is not null order by 1;
SELECT DISTINCT 'alter '||object_type||' '||owner||'.'||object_name||' compile;' FROM dba_objects WHERE (owner, object_name) IN
(select du.name, d.name d_name from sys."_ACTUAL_EDITION_OBJ" d, sys.user$ du, sys.dependency$ dep, sys."_ACTUAL_EDITION_OBJ" p, sys.user$ pu
   where d.obj# = dep.d_obj# and p.obj# = dep.p_obj# and d.owner# = du.user# and p.owner# = pu.user#
     and d.status = 1 and bitand(dep.property, 1) = 1 and d.subname is null and not(p.type# = 32 and d.type# = 1)
     and not(p.type# = 29 and d.type# = 5) and not(p.type# in(5, 13) and d.type# in (2, 55)) and (p.status not in (1, 2, 4) or p.stime != dep.p_timestamp)
UNION
select pu.name, p.name p_name from sys."_ACTUAL_EDITION_OBJ" d, sys.user$ du, sys.dependency$ dep, sys."_ACTUAL_EDITION_OBJ" p, sys.user$ pu
   where d.obj# = dep.d_obj# and p.obj# = dep.p_obj# and d.owner# = du.user# and p.owner# = pu.user# and d.status = 1
     and bitand(dep.property, 1) = 1 and d.subname is NULL and not(p.type# = 32 and d.type# = 1) and not(p.type# = 29 and d.type# = 5)
     and not(p.type# in(5, 13) and d.type# in (2, 55)) and (p.status not in (1, 2, 4) or p.stime != dep.p_timestamp));
prompt
prompt ============ Trigger Problems ===============================================
-- Broken triggers (invalid and enabled)
SELECT 'Broken trigger: '||t.owner||'.'||t.trigger_name broken_triggers FROM dba_triggers t
  JOIN dba_objects o ON (o.owner = t.owner AND o.object_name = t.trigger_name AND o.object_type = 'TRIGGER')
 WHERE o.status <> 'VALID' AND t.status = 'ENABLED';
-- Triggers not owned by the table owner
SELECT 'Owner problem: '||owner||'.'||trigger_name trig_name,table_owner||'.'||table_name tab_name FROM dba_triggers WHERE owner <> table_owner AND trigger_type NOT LIKE '%EVENT';
-- Disabled triggers 
SELECT status,owner||'.'||trigger_name FROM dba_triggers WHERE status <> 'ENABLED' AND owner NOT LIKE 'APEX%' AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA');
prompt
prompt ============ Fix Service Account Synonyms ===================
prompt
SELECT 'create synonym MC_SERV1.'||table_name||' for '||owner||'.'||table_name||';' FROM (SELECT owner, table_name FROM dba_tab_privs 
WHERE grantee IN (SELECT DISTINCT granted_role FROM dba_role_privs START WITH grantee = 'SERV1' CONNECT BY PRIOR granted_role = grantee) OR grantee = 'SERV1'
MINUS SELECT table_owner, table_name FROM dba_synonyms WHERE owner IN ('SERV1','PUBLIC'));
SELECT 'create synonym MC_SERV2.'||table_name||' for '||owner||'.'||table_name||';' FROM (SELECT owner, table_name FROM dba_tab_privs 
WHERE grantee IN (SELECT DISTINCT granted_role FROM dba_role_privs START WITH grantee = 'SERV2' CONNECT BY PRIOR granted_role = grantee) OR grantee = 'SERV2'
MINUS SELECT table_owner, table_name FROM dba_synonyms WHERE owner IN ('SERV2','PUBLIC'));
prompt ============ User Account Problems ==========================================
set lines 120
set pages 600
col username for a40
col profile for a12
col account_status for a20
col "Last Change Date" for a18
col "Profile" for 99
SELECT 'Password needs change: '||u.username "USERNAME", u.profile, max(h.password_date) "Last Change Date", u.account_status
 FROM dba_users u LEFT OUTER JOIN sys.user_history$ h ON (h.user# = u.user_id)
 WHERE u.profile = 'EMPACCT' AND  (h.password_date IS NULL OR u.account_status NOT IN ('OPEN'))
 GROUP BY u.username, u.profile, u.account_status
 ORDER BY max(h.password_date) DESC NULLS LAST, u.username;
SELECT '-- '||username||' has default password!'||chr(10)||'alter user '||username||' identified by "'||'<new password>'||'";' FROM dba_users_with_defpwd where username NOT IN ('XS\$NULL');
SELECT 'alter user '||username||' temporary tablespace '||
       (SELECT property_value FROM database_properties WHERE property_name = 'DEFAULT_TEMP_TABLESPACE')||';'
  FROM dba_users u WHERE temporary_tablespace <>
       (SELECT property_value FROM database_properties WHERE property_name = 'DEFAULT_TEMP_TABLESPACE');
PROMPT Passwords to change or expire:
SELECT NAME "Name", ptime "Last password change", resource$ "Profile" FROM sys.user$ WHERE astatus = 0 AND type# = 1 AND ptime < SYSDATE - 90 ORDER BY resource$, NAME;

prompt
prompt ============ Elevated Privileges  ================================================
SELECT 'SYSDBA: ' || username FROM v\$pwfile_users WHERE username <> 'SYS';
SELECT 'DBA: ' || grantee FROM dba_role_privs WHERE granted_role = 'DBA' AND grantee NOT LIKE 'SYS%';
prompt Missing Quota
SELECT 'alter user ' || owner || ' quota unlimited on ' || tablespace_name || ';' FROM (SELECT DISTINCT owner, tablespace_name FROM dba_segments 
  WHERE owner NOT IN (SELECT grantee FROM dba_sys_privs WHERE privilege = 'UNLIMITED TABLESPACE') MINUS SELECT username, tablespace_name FROM dba_ts_quotas WHERE max_bytes = -1); 
prompt
prompt ============ DataGuard Configuration ================================================
SET lines 200
COL NAME FOR A30
COL VALUE FOR A150
SELECT NAME, VALUE FROM v\$parameter WHERE VALUE IS NOT NULL
 AND ((NAME LIKE 'log_archive_%' AND NAME NOT LIKE 'log_archive_dest_state%') OR NAME LIKE 'fal%' OR
       NAME LIKE 'db%name' OR (NAME LIKE 'log_archive_dest_state%' AND upper(VALUE) <> 'ENABLE'))
 ORDER BY 1;

spool off
exit
!

# If an email address is given, send the report to that address
if [ -n "${MAILTO}" ] ; then
  echo Mailing ${REPORT_NAME} to ${MAILTO}
  /usr/local/bin/sendEmail-v1.56/sendEmail -f $USER@`hostname` -t ${MAILTO} -u "${REPORT_TITLE}" -s mail.example.com -o message-file=${REPORT_NAME}
fi

