# GatherStats.sh - Gather table stats based on time and size (number of records)
# 
# Author: Dennis Heltzel

. /home/oracle/bin/ora_funcs.sh
ORACLE_BASE=/u01/app/oracle
ORACLE_HOME=${ORACLE_BASE}/product/12.1.0.2/DbHome_2
PATH=$PATH:$ORACLE_HOME/bin

CRED=${CRED:-/}

usage() {
  echo "Usage: $0 [-t days] [-r num_recs] [-d database name] [-s] [-f filter_string]"
  echo "  -t days - only select tables that have not had stats gathered in at least this many days (default 7)"
  echo "  -p days - only select partitions that have not had stats gathered in at least this many days (default 180)"
  echo "  -r num_recs - only select tables with fewer than X thousand records (default is unlimited)"
  echo "  -d database name - defaults to $ORACLE_SID"
  echo "  -s - also gather system stats (takes a long time)"
  echo "  -f filter_string - arbitrary filter for the select query (ex. \"AND s.owner='DBADMIN'\")"
  exit 1
}

# Handle parameters
while getopts ":d:t:p:r:sf:" opt; do
  case $opt in
    d)
      DB_NAME=$OPTARG
      ;;
    t)
      AGE_DAYS=$OPTARG
      ;;
    p)
      PART_AGE_DAYS=$OPTARG
      ;;
    r)
      NUM_RECS="AND t.num_rows < ($OPTARG * 1000) "
      ;;
    s)
      SYS_STATS=Y
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

oe ${DB_NAME}
DB_NAME=${DB_NAME:-${ORACLE_SID}}
#echo "DB_NAME=${DB_NAME}:ORACLE_SID=${ORACLE_SID}:"

AGE_DAYS=${AGE_DAYS:-7}
PART_AGE_DAYS=${PART_AGE_DAYS:-180}
LOG_DIR=/cloudfs/logs
BASE_NAME=${LOG_DIR}/GatherStats_${DB_NAME}
SQL_NAME=${BASE_NAME}.sql
LOG_FILE=${BASE_NAME}.log
#echo "${AGE_DAYS}"
#echo "${NUM_RECS}"
#echo "${SQL_NAME}"
#echo "${OPT_FILTER}"

:> ${LOG_FILE}
exec >> $LOG_FILE 2>&1

echo "Gathering stats for tables in ${DB_NAME} with stats older that ${AGE_DAYS} days . . ."

(sqlplus -s ${CRED} as sysdba <<!
set pages 0
set feed off
set head off
set lines 180
prompt set sqlprompt "_CONNECT_IDENTIFIER> ";
prompt set feed off;
prompt set echo on;
prompt set time on;
prompt set timi on;
prompt spool ${LOG_FILE}
SELECT 'exec DBMS_STATS.GATHER_TABLE_STATS('''||t.owner||''',''"'||t.table_name||'"'',CASCADE=>TRUE);' FROM dba_tables t
 JOIN dba_tab_statistics s ON (s.OWNER = t.OWNER AND s.TABLE_NAME = t.TABLE_NAME)
 WHERE t.owner IN (SELECT username FROM dba_users WHERE profile = 'DATACCT') AND t.temporary = 'N' AND t.secondary = 'N' AND t.segment_created = 'YES'
 AND (t.owner,t.table_name) NOT IN (SELECT owner, table_name FROM dba_external_tables)
 AND s.stattype_locked IS NULL AND (t.last_analyzed < SYSDATE -  ${AGE_DAYS} OR t.last_analyzed IS NULL) AND t.table_name NOT LIKE 'SYS%' ${NUM_RECS} ${OPT_FILTER}
 ORDER BY t.num_rows;
SELECT 'exec DBMS_STATS.GATHER_TABLE_STATS('''||t.table_owner||''',''"'||t.table_name||'"'','''||t.partition_name||''',granularity=>''APPROX_GLOBAL AND PARTITION'',CASCADE=>TRUE);' FROM dba_tab_partitions t
 JOIN dba_tab_statistics s ON (s.OWNER = t.table_owner AND s.TABLE_NAME = t.TABLE_NAME AND s.partition_name = t.partition_name)
 WHERE t.table_owner IN (SELECT username FROM dba_users WHERE profile = 'DATACCT') AND t.segment_created = 'YES'
 AND (t.table_owner,t.table_name) NOT IN (SELECT owner, table_name FROM dba_external_tables)
 AND s.stattype_locked IS NULL
 AND t.last_analyzed IS NULL
-- AND ((t.last_analyzed < SYSDATE - ${PART_AGE_DAYS}) OR t.last_analyzed IS NULL)
 AND t.table_name NOT LIKE 'SYS%' ${NUM_RECS} ${OPT_FILTER}
 ORDER BY t.num_rows;
exit
!
) > ${SQL_NAME}

# Add commands to gather system stats if requested
if [ -n "${SYS_STATS}" ] ; then
  echo "exec DBMS_STATS.GATHER_SYSTEM_STATS" >>${SQL_NAME}
  echo "exec DBMS_STATS.GATHER_DICTIONARY_STATS" >>${SQL_NAME}
  echo "exec DBMS_STATS.GATHER_FIXED_OBJECTS_STATS" >>${SQL_NAME}
fi
echo "exit" >>${SQL_NAME}

sqlplus ${CRED} as sysdba @${SQL_NAME}
