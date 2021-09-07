# Generate SQL to maintain Oracle jobs - both DBA_SCHEDULER_JOBS and DBA_JOBS
#
# File $Id: JobMaintenance.sh 3366 2014-03-18 20:14:51Z dheltzel $
# Modified $Author: dheltzel $ 
# Date $Date: 2014-03-18 16:14:51 -0400 (Tue, 18 Mar 2014) $
# Revision $Revision: 3366 $

CRED=${CRED:-/}

usage() {
  echo "Usage: $0 [-i] [-c] [-d database name]"
  echo "  -i - interactive (allows you to run the SQL that is generated"
  echo "  -c - check or count, only counts the number of jobs that are enabled"
  echo "  -d database name - defaults to $ORACLE_SID"
  echo " "
  echo "This script creates 2 files, containing commands to disable and enable the currently enabled jobs."
  echo "It handles both DBMS_JOBS and DBMS_SCHEDULER_JOBS"
  echo "The .sql files contain the database name and a timestamp to avoid overwriting existing files"
  echo "Run the disable SQL before the maintenance starts, and the enable SQL after it completes, to restore operations as they were"
  echo "If you are running this from a remote host (using TNS), you will need to set the CRED env var to a user/passwd with SYSDBA established in the orapwd files"
  exit 1
}

# Handle parameters
while getopts ":d:ic" opt; do
  case $opt in
    d)
      TWO_TASK=$OPTARG
      DB_NAME=$OPTARG
      ;;
    c)
      COUNT_ONLY=Y
      ;;
    i)
      INTERACTIVE=Y
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
if [ "${COUNT_ONLY}" = "Y" ] ; then
  echo "${DB_NAME}"
  (sqlplus -s ${CRED} as sysdba <<!
set pages 0
set feed off
set head off
set lines 130
SELECT 'DBMS_SCHEDULER enabled: '||count(*) FROM dba_scheduler_jobs WHERE enabled = 'TRUE';
SELECT 'DBMS_JOBS enabled: '||count(*) FROM dba_jobs WHERE broken = 'N';
exit
!
)
  exit 0
fi

DISABLE_SQL=JobDisable_${DB_NAME}-`date "+%y%m%d%H%M"`.sql
DISABLE_LOG=JobDisable_${DB_NAME}-`date "+%y%m%d%H%M"`.log
ENABLE_SQL=JobEnable_${DB_NAME}-`date "+%y%m%d%H%M"`.sql
ENABLE_LOG=JobEnable_${DB_NAME}-`date "+%y%m%d%H%M"`.log

echo "Generating SQL to disable and enable Oracle jobs"
echo
(sqlplus -s ${CRED} as sysdba <<!
set pages 0
set feed off
set head off
set lines 130
spool ${DISABLE_SQL}
prompt set sqlprompt "_CONNECT_IDENTIFIER> ";
prompt set feed off;
prompt set echo on;
prompt spool ${DISABLE_LOG};
SELECT 'exec sys.dbms_scheduler.disable('''||owner||'.'||job_name||''')' disable_cmd FROM dba_scheduler_jobs WHERE enabled = 'TRUE';
SELECT 'exec sys.dbms_ijob.broken('||job||', TRUE)' FROM dba_jobs WHERE broken = 'N';
prompt SELECT 'exec sys.dbms_scheduler.stop_job('''||owner||'.'||job_name||''', TRUE)' stop_cmd FROM dba_scheduler_jobs WHERE enabled = 'TRUE';;
prompt SELECT 'exec sys.dbms_scheduler.disable('''||owner||'.'||job_name||''')' disable_cmd FROM dba_scheduler_jobs WHERE enabled = 'TRUE';
spool ${ENABLE_SQL}
prompt set sqlprompt "_CONNECT_IDENTIFIER> ";
prompt set feed off;
prompt set echo on;
prompt spool ${ENABLE_LOG};
SELECT 'exec sys.dbms_scheduler.enable('''||owner||'.'||job_name||''')' enable_cmd FROM dba_scheduler_jobs WHERE enabled = 'TRUE';
SELECT 'exec sys.dbms_ijob.broken('||job||', FALSE)' FROM dba_jobs WHERE broken = 'N';
spool off
SELECT 'DBMS_SCHEDULER enabled: '||count(*) FROM dba_scheduler_jobs WHERE enabled = 'TRUE';
SELECT 'DBMS_JOBS enabled: '||count(*) FROM dba_jobs WHERE broken = 'N';
exit
!
)

echo
echo "job disable commands for ${DB_NAME} are in ${DISABLE_SQL}"
echo "job enable commands for ${DB_NAME} are in ${ENABLE_SQL}"

if [ "${INTERACTIVE}" = "Y" ] ; then
  echo "Do you want to run the Disable SQL in ${DB_NAME} ?"
  read ans
  if [ "$ans" = "Y" ] ; then
    echo sqlplus ${CRED} as sysdba @${DISABLE_SQL}
    echo Output spooled to ${DISABLE_LOG}
  fi
  echo "Do you want to run the Enable SQL in ${DB_NAME} ?"
  read ans
  if [ "$ans" = "Y" ] ; then
    echo sqlplus ${CRED} as sysdba @${ENABLE_SQL}
    echo Output spooled to ${ENABLE_LOG}
  fi
fi

