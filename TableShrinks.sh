# Reorganise the rows in the tables with "alter table shrink"
#
# File $Id: TableShrinks.sh 2414 2014-01-22 15:51:11Z dheltzel $
# Modified $Author: dheltzel $ 
# Date $Date: 2014-01-22 10:51:11 -0500 (Wed, 22 Jan 2014) $
# Revision $Revision: 2414 $

CRED=${CRED:-/}
RUN_DDL=Y
CASCADE=CASCADE
COMPACT=""
RUNDIR=`dirname "${BASH_SOURCE[0]}"`
EXCLUDE_FILE=${RUNDIR}/TableShrinks_exclude.lst

usage() {
  echo "Usage: $0 [-n ] [-r num_recs] [-d ] [-s] [-f filter_string]"
  echo "  -n - no changes, only create files with DDL to run"
  echo "  -r num_recs - only select tables with fewer than X thousand records (default is unlimited)"
  echo "  -d - data rows only, (no cascade option)"
  echo "  -s - safe mode, add the compact to avoid all table level locking (also does not free any space)"
  echo "  -f filter_string - arbitrary filter for the select query (ex. \"AND owner='DBADMIN'\")"
  exit 1
}

# Handle parameters
while getopts ":r:ndsf:" opt; do
  case $opt in
    n)
      RUN_DDL=N
      ;;
    r)
      NUM_RECS="AND num_rows < $OPTARG * 1000"
      ;;
    d)
      CASCADE=""
      ;;
    s)
      COMPACT="COMPACT"
      ;;
    f)
      OPT_FILTER=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
      ;;
  esac
done

FB_CHECK=`sqlplus -s ${CRED} as sysdba <<! 
SET FEED OFF
SET serverout ON SIZE unlimited
DECLARE
  fl_status VARCHAR2(30);
  cnt       PLS_INTEGER := 1;
BEGIN
  SELECT flashback_on INTO fl_status FROM v\\$database;
  IF (fl_status = 'RESTORE POINT ONLY') THEN
    SELECT COUNT(*) INTO cnt FROM v\\$restore_point;
  END IF;
  IF (fl_status = 'NO' OR cnt = 0) THEN
    dbms_output.put_line('OK');
  ELSE
    dbms_output.put_line('FB issue');
  END IF;
END;
/
exit
!`

if [ ! "${FB_CHECK}" = "OK" ] ; then
  echo "Flashback in use, do not shrink"
  exit 1
fi

CLONEDB=`sqlplus -s ${CRED} as sysdba <<! 
set head off
set feed off
SELECT VALUE FROM v\\$parameter WHERE NAME = 'clonedb';
!`
if [ "${CLONEDB}" = "TRUE" ] ; then
  echo "CloneDB database, do not shrink"
  exit 1
fi

echo "Size clause: ${NUM_RECS}"
echo "Run DDL: ${RUN_DDL}"
echo "Cascade option: ${CASCADE}"
echo "Compact option: ${COMPACT}"
#echo "Press Enter to continue with these settings"
#read x

# Enable row movement on any tables that need it
REPORT_NAME=TS_EnableRowMovement_${ORACLE_SID}-`date "+%y%m%d%H%M"`.sql
echo "Enable row movement SQL: ${REPORT_NAME}"
(sqlplus -s ${CRED} as sysdba <<! 
set ver off
set pages 0
set serverout on size unlimited
set feed off
set head off
set lines 130
prompt set echo on;
SELECT 'alter table ' || owner || '."' || table_name || '" enable row movement;' FROM dba_tables
 WHERE row_movement = 'DISABLED' AND iot_type is null AND temporary = 'N' ${NUM_RECS}
 AND owner not like '%SYS%' AND owner NOT IN ('OUTLN','XDB','GSMADMIN_INTERNAL','GGS')
 AND (owner, table_name) NOT IN (SELECT owner, mview_name FROM dba_mviews)
 AND (owner, table_name) NOT IN (SELECT log_owner, log_table FROM dba_mview_logs)
 AND compression = 'DISABLED'
 ${OPT_FILTER};
prompt exit
exit
!
) >${REPORT_NAME}

if [ "${RUN_DDL}" = 'Y' ] ; then
  echo "Enable row movement starting at `date` output: ${REPORT_NAME}.lst"
  sqlplus ${CRED} as sysdba @${REPORT_NAME} > ${REPORT_NAME}.lst
  echo "Enable row movement completed at `date`"
fi

# Perform the shrinks
REPORT_NAME=TS_ShrinkTables_${ORACLE_SID}-`date "+%y%m%d%H%M"`.sql
echo "Table Shrink SQL: ${REPORT_NAME}"
(sqlplus -s ${CRED} as sysdba <<!
set ver off
set pages 0
set serverout on size unlimited
set feed off
set head off
set lines 130
prompt set time on;
prompt set timi on;
prompt set head off;
prompt SELECT 'Starting size (MB): '||TO_CHAR(SUM(bytes)/1024/1024, '999,999,999,999.9') FROM dba_segments WHERE owner NOT LIKE '%SYS%' AND owner NOT IN ('OUTLN', 'XDB','GSMADMIN_INTERNAL','GGS');;
prompt set echo on;
SELECT 'alter table ' || owner || '."' || table_name || '" shrink space ${COMPACT} ${CASCADE};' FROM dba_tables
 WHERE row_movement = 'ENABLED' AND segment_created = 'YES' AND iot_type is null AND temporary = 'N' ${NUM_RECS}
 AND partitioned = 'NO' AND compression = 'DISABLED' AND read_only = 'NO' AND compression = 'DISABLED'
 AND owner not like '%SYS%' AND owner NOT IN ('OUTLN','XDB','GSMADMIN_INTERNAL','GGS','VIZ')
 AND (owner, table_name) NOT IN (SELECT owner, mview_name FROM dba_mviews)
 AND (owner, table_name) NOT IN (SELECT log_owner, log_table FROM dba_mview_logs) ${OPT_FILTER}
 AND (owner, table_name) NOT IN (SELECT DISTINCT table_owner,table_name FROM dba_indexes WHERE index_type LIKE 'FUN%')
 ORDER BY num_rows;

SELECT 'alter table ' || table_owner || '.' || table_name || ' modify partition ' || partition_name || ' shrink space;' FROM dba_tab_partitions tp
 WHERE segment_created = 'YES' AND compression = 'DISABLED' AND (table_owner, table_name) IN
 (SELECT owner, table_name FROM dba_tables WHERE iot_type IS NULL AND temporary = 'N' AND owner NOT LIKE '%SYS%' AND owner NOT IN ('OUTLN', 'XDB','GSMADMIN_INTERNAL','GGS','VIZ')
  AND (owner, table_name) NOT IN (SELECT owner, mview_name FROM dba_mviews)
  AND (owner, table_name) NOT IN (SELECT log_owner, log_table FROM dba_mview_logs) ${OPT_FILTER})
 AND (table_owner, table_name) NOT IN (SELECT owner, mview_name FROM dba_mviews)
 AND (table_owner, table_name) NOT IN (SELECT log_owner, log_table FROM dba_mview_logs)
 AND (table_owner, table_name) NOT IN (SELECT DISTINCT table_owner,table_name FROM dba_indexes WHERE index_type LIKE 'FUN%')
 AND tp.partition_name NOT LIKE '%0000' AND tp.compression = 'DISABLED'
 ORDER BY num_rows;

--SELECT 'alter table ' || table_owner || '.' || table_name || ' modify subpartition ' || subpartition_name || ' shrink space;' FROM dba_tab_subpartitions tp
-- WHERE segment_created = 'YES' AND compression = 'DISABLED' AND (table_owner, table_name) IN
-- (SELECT owner, table_name FROM dba_tables WHERE iot_type IS NULL AND temporary = 'N' AND owner NOT LIKE '%SYS%' AND owner NOT IN ('OUTLN', 'XDB','GSMADMIN_INTERNAL','GGS','VIZ')
--  AND (owner, table_name) NOT IN (SELECT owner, mview_name FROM dba_mviews)
--  AND (owner, table_name) NOT IN (SELECT log_owner, log_table FROM dba_mview_logs) ${OPT_FILTER})
-- AND (table_owner, table_name) NOT IN (SELECT owner, mview_name FROM dba_mviews)
-- AND (table_owner, table_name) NOT IN (SELECT log_owner, log_table FROM dba_mview_logs)
-- ORDER BY num_rows;

prompt set echo off;
prompt SELECT 'Ending size (MB):   '||TO_CHAR(SUM(bytes)/1024/1024, '999,999,999,999.9') FROM dba_segments WHERE owner NOT LIKE '%SYS%' AND owner NOT IN ('OUTLN', 'XDB','GSMADMIN_INTERNAL','GGS','VIZ');;
prompt exit
exit
!
) | fgrep -v -f ${EXCLUDE_FILE} >${REPORT_NAME}

if [ "${RUN_DDL}" = 'Y' ] ; then
  echo "Table Shrink starting at `date` output: ${REPORT_NAME}.lst"
  sqlplus ${CRED} as sysdba @${REPORT_NAME} > ${REPORT_NAME}.lst
  echo "Table Shrink completed at `date`"
  grep "size (MB)" ${REPORT_NAME}.lst
fi
