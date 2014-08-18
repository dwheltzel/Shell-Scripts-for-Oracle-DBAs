# Gather table stats based on time and size (number of records)
#
# written by Dennis Heltzel

CRED=${CRED:-/}

usage() {
  echo "Usage: $0 [-t days] [-r num_recs] [-d database name] [-s] [-f filter_string]"
  echo "  -t days - only select tables that have not had stats gathered in at least this many days (default 7)"
  echo "  -r num_recs - only select tables with fewer than X thousand records (default is unlimited)"
  echo "  -d database name - defaults to $ORACLE_SID"
  echo "  -s - also gather system stats (takes a long time)"
  echo "  -f filter_string - arbitrary filter for the select query (ex. \"AND s.owner='DBADMIN'\")"
  exit 1
}

# Handle parameters
while getopts ":d:t:r:sf:" opt; do
  case $opt in
    d)
      TWO_TASK=$OPTARG
      DB_NAME=$OPTARG
      ;;
    t)
      AGE_DAYS=$OPTARG
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

DB_NAME=${DB_NAME:-${ORACLE_SID}}
AGE_DAYS=${AGE_DAYS:-7}
REPORT_NAME=GatherStats_${DB_NAME}-`date "+%y%m%d%H%M"`.sql
LOG_NAME=GatherStats_${DB_NAME}-`date "+%y%m%d%H%M"`.log
#echo "${AGE_DAYS}"
#echo "${NUM_RECS}"
#echo "${REPORT_NAME}"
#echo "${OPT_FILTER}"
echo "Gathering stats for tables in ${DB_NAME} with stats older that ${AGE_DAYS} days . . ."

(sqlplus -s ${CRED} as sysdba <<!
set pages 0
set feed off
set head off
set lines 130
prompt set sqlprompt "_CONNECT_IDENTIFIER> ";
prompt set feed off;
prompt set echo on;
--prompt spool ${LOG_NAME}
SELECT 'exec DBMS_STATS.GATHER_TABLE_STATS('''||t.owner||''','''||t.table_name||''');' FROM dba_tables t
 JOIN dba_tab_statistics s ON (s.OWNER = t.OWNER AND s.TABLE_NAME = t.TABLE_NAME)
 WHERE t.owner NOT LIKE '%SYS%' AND t.owner NOT IN ('XDB') AND t.temporary = 'N' AND t.secondary = 'N' AND t.segment_created = 'YES'
 AND (t.owner,t.table_name) NOT IN (SELECT owner, table_name FROM dba_external_tables)
 AND s.stattype_locked IS NULL AND (t.last_analyzed < SYSDATE -  ${AGE_DAYS} OR t.last_analyzed IS NULL) AND t.table_name NOT LIKE 'SYS%' ${NUM_RECS} ${OPT_FILTER}
 ORDER BY t.num_rows;
exit
!
) > ${REPORT_NAME}

# Add commands to gather system stats if requested
if [ -n "${SYS_STATS}" ] ; then
  echo "exec DBMS_STATS.GATHER_SYSTEM_STATS" >>${REPORT_NAME}
  echo "exec DBMS_STATS.GATHER_DICTIONARY_STATS" >>${REPORT_NAME}
  echo "exec DBMS_STATS.GATHER_FIXED_OBJECTS_STATS" >>${REPORT_NAME}
fi
echo "exit" >>${REPORT_NAME}

sqlplus ${CRED} as sysdba @${REPORT_NAME}
