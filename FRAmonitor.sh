# Monitors the percent used of the FRA
#
# Author: Dennis Heltzel

RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh
export ORACLE_SID=CDB1
#export ORACLE_BASE=/i01/app/oracle
#export ORACLE_HOME=$ORACLE_BASE/product/11.2.0.3/db1
#export PATH=$PATH:$ORACLE_HOME/bin

CRED=${CRED:-/}
LOG_DIR=~/logs
LOG_FILE=$LOG_DIR/FRA_$ORACLE_SID.log
A1_FILE=$LOG_DIR/FRA_ActualUsage.last
A2_FILE=$LOG_DIR/FRA_LogicalUsage.last
RUNWAY_FILE=$LOG_DIR/FRA_runway.last
EMAIL_FILE=$LOG_DIR/FRA_email.last

usage() {
  echo "Usage: $0 [-l log file name] [-a alert file name] [-d database name] [-r] [-e email recipients]"
  echo "  -l log file name - name of the file to append the logging data. Default: $LOG_FILE"
  echo "  -a alert file name - name of the file to write the last value to. Default: $A1_FILE"
  echo "  -d database name - defaults to $ORACLE_SID"
  echo "  -r - only report on the last run"
  echo "  -e email recipients - send alert to these addresses if any levels are exceeded"
  exit 1
}

# Handle parameters
while getopts ":l:a:d:e:r" opt; do
  case $opt in
    l)
      LOG_FILE=$OPTARG
      ;;
    a)
      A1_FILE=$OPTARG
      ;;
    d)
      export ORACLE_SID=$OPTARG
      ;;
    e)
      export MAIL_TO=$OPTARG
      export MAILX=/usr/local/bin/sendEmail-v1.56/sendEmail
      export SMTP_SERVER=localhost
      export SENDER="`hostname`@comspoc.com"
      ;;
    r)
      echo "Percent of actual space used: `cat $A1_FILE`"
      echo "Percent of logical space used: `cat $A2_FILE`"
      echo -n "FRA runway (hours) `cat $RUNWAY_FILE`   (days) "
      python -c "print `cat $RUNWAY_FILE` / 24"
      exit
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

oe $ORACLE_SID >/dev/null

FRA_PCT1=`sqlplus -s ${CRED} as sysdba <<!
set pages 0
set trimspool on
set feed off
col a for 999
spool $A1_FILE
SELECT trim(round(space_used/space_limit*100)) a FROM v\\$recovery_file_dest;
exit
!`

FRA_PCT2=`sqlplus -s ${CRED} as sysdba <<!
set pages 0
set trimspool on
set feed off
col a for 999
spool $A2_FILE
SELECT trim(round((space_used-space_reclaimable)/space_limit*100)) a FROM v\\$recovery_file_dest;
exit
!`

FRA_RUNWAY=`sqlplus -s ${CRED} as sysdba <<!
set pages 0
set trimspool on
set feed off
col a for 999,999.9
spool $RUNWAY_FILE
-- Hours of Redo runway left, 6 hour rolling avg
SELECT TRIM(ROUND((space_limit-space_used-space_reclaimable) /
  (SELECT SUM(blocks*block_size)/6 FROM v\\$archived_log WHERE deleted = 'NO' AND is_recovery_dest_file = 'YES' AND completion_time > SYSDATE-6/24),1)) a
  FROM v\\$recovery_file_dest;
exit
!`

#echo "FRA_PCT1 $FRA_PCT1"

#tty -s && echo "$FRA_PCT1"
echo "`date "+%x %X"` - $FRA_PCT1   $FRA_PCT2    $FRA_RUNWAY" >> $LOG_FILE

if [ -n "$MAIL_TO" ] ; then
  #if [ `cut -d. -f1 $RUNWAY_FILE` -lt 48 ] ; then
  if [ "$FRA_PCT2" -gt 60 ] ; then
    echo "Percent of actual space used: `cat $A1_FILE`" >$EMAIL_FILE
    echo "Percent of logical space used: `cat $A2_FILE`" >>$EMAIL_FILE
    echo -n "FRA runway (hours) `cat $RUNWAY_FILE`   (days) " >>$EMAIL_FILE
    python -c "print `cat $RUNWAY_FILE` / 24" >>$EMAIL_FILE
    ${MAILX} -f ${SENDER} -t ${MAIL_TO} -s ${SMTP_SERVER} -u "FRA Alert" -o message-file=${EMAIL_FILE} >/dev/null
  fi
fi
