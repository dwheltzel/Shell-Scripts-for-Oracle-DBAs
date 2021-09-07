#! /bin/bash
#################################################################
# Description:  This script rotates oracle db and listener logs
# File $Id: cycle_db_logs.sh 2741 2014-02-13 22:33:58Z dheltzel $
# Modified $Author: dheltzel $ 
# Date $Date: 2014-02-13 17:33:58 -0500 (Thu, 13 Feb 2014) $
# Revision $Revision: 2741 $
#################################################################

. ~/.bashrc
HOME_DIR=`dirname "${BASH_SOURCE[0]}"`
. ${HOME_DIR}/ora_funcs.sh
export ORACLE_BASE=${ORACLE_BASE:-/u001/app/oracle}
export MY=`date +"%b-%Y"`
export MYD=`date +"%m%d%y"`
KEEP_DAYS=45
LOGFILE=${HOME_DIR}/`basename $0 .sh`.log

usage() {
  echo "Usage: $0 [-k keep days] [-b backup_directory] [-l log directory]"
  echo "  -k keep days - number of days to keep archives files (default is ${KEEP_DAYS})"
  echo "  -b backup_directory - store all backup files in this location (default is the location of the original files)"
  echo "  -l log directory - location where the logfiles are written (default is the directory the script is run from)"
  exit 1
}

# Handle parameters
while getopts ":k:b:l:" opt; do
  case $opt in
    k)
      KEEP_DAYS=$OPTARG
      ;;
    b)
      COMMON_BACKUP_DIR=$OPTARG
      # try to create the directory if it does not exist
      [ -d "${COMMON_BACKUP_DIR}" ] || mkdir -p ${COMMON_BACKUP_DIR}
      # If we can't wrote to the directory, don't use it
      touch ${COMMON_BACKUP_DIR}/last_backup.txt || unset COMMON_BACKUP_DIR
      ;;
    l)
      LOGDIR=$OPTARG
      # try to create the directory if it does not exist
      [ -d "${LOGDIR}" ] || mkdir -p ${LOGDIR}
      # Only set the logfile if we are able to write to it
      touch ${LOGDIR}/`basename $0 .sh`_${MYD}.log && LOGFILE=${LOGDIR}/`basename $0 .sh`_${MYD}.log
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

tty -s && echo "Logging to $LOGFILE"
exec 1>> $LOGFILE 2>&1
echo "**********************"
echo "Starting log management at `date`"
echo "Keeping ${KEEP_DAYS} days of archived logs"

for DBINST in $( ps -ef|grep ora_\\pmon| cut -d_ -f3-); do
   echo "**********************"
   echo -n "Processing logs for "
   oe ${DBINST} || continue

   #Find trace base directory
   TRACE_BASE_DIR=`sqlplus -s / as sysdba <<!
set pages 0
select value from v\\$diag_info where name='ADR Home';
exit
!`
   DBNAME=`sqlplus -s / as sysdba <<!
set pages 0
select value from v\\$parameter where name='db_name';
exit
!`
   ADUMP_DEST=`sqlplus -s / as sysdba <<!
set pages 0
select value from v\\$parameter where name='audit_file_dest';
exit
!`
   if [ -z "$TRACE_BASE_DIR" -o -z "$DBNAME" ] ; then
      echo "TRACE_BASE_DIR or DBNAME variables null"
      exit 1
   fi

   if [ -n "$COMMON_BACKUP_DIR" ] ; then
     BACKUP_DIR=$COMMON_BACKUP_DIR
   else
     BACKUP_DIR=$TRACE_BASE_DIR/trace
   fi
   echo "Archiving files to ${BACKUP_DIR}"
   cd $TRACE_BASE_DIR/trace

   # If monthly consolidated alert log not present then create it
   ALERT_LOG=${TRACE_BASE_DIR}/trace/alert_${ORACLE_SID}.log
   MONTHLY_ALERT_LOG=${BACKUP_DIR}/alert_${ORACLE_SID}_$MY.log
   echo "Backup copy alert log: append contents of ${ALERT_LOG} to ${MONTHLY_ALERT_LOG}"
   #echo "ALERT_LOG: $ALERT_LOG"
   #echo "MONTHLY_ALERT_LOG: $MONTHLY_ALERT_LOG"
   if [ -r "${ALERT_LOG}" ] ; then
     #echo "touch $MONTHLY_ALERT_LOG"
     touch $MONTHLY_ALERT_LOG
     cat alert_"${ORACLE_SID}".log >> $MONTHLY_ALERT_LOG
     cat /dev/null > alert_"${ORACLE_SID}".log
   fi

   echo "Backup trace files in `pwd`"
   DAILY_TRC_ARCHIVE=${BACKUP_DIR}/${DBINST}_tracefiles_${MYD}.tgz
   if [ -s "${DAILY_TRC_ARCHIVE}" ] ; then
     echo "Renaming ${DAILY_TRC_ARCHIVE}"
     mv ${DAILY_TRC_ARCHIVE} ${DAILY_TRC_ARCHIVE}.`date +%H%M%S`
   fi
#/sbin/fuser -a ./.* 2>&1|grep ":$"|sed -e "s/://"
   ls *.trc *.trm >/dev/null 2>&1 && tar -czf ${DAILY_TRC_ARCHIVE} *.trc *.trm && /sbin/fuser -a *trc *trm 2>&1|grep ":$"|sed -e "s/://"|grep -v "*"|xargs rm -f

   echo "Delete alert xml files from $TRACE_BASE_DIR/alert"
   find $TRACE_BASE_DIR/alert -name "*.xml" -mtime +0 -exec cp /dev/null {} \;
   find $TRACE_BASE_DIR/alert -name "*.xml" -mtime +30 -delete

   echo "Backup archive core dump files"
   CORE_FILE_CNT=`ls -ld cdmp* 2>/dev/null|wc -l`
   if [ "${CORE_FILE_CNT}" -gt 0 ] ; then
     DAILY_CDMP_ARCHIVE=${BACKUP_DIR}/${DBINST}_cdump_${MYD}.tgz
     if [ -s "${DAILY_CDMP_ARCHIVE}" ] ; then
       echo "Renaming ${DAILY_CDMP_ARCHIVE}"
       mv ${DAILY_CDMP_ARCHIVE} ${DAILY_CDMP_ARCHIVE}.`date +%H%M%S`
     fi
     tar -czf ${DAILY_CDMP_ARCHIVE} cdmp* && rm -rf cdmp*
   fi

   if [ -n "$COMMON_BACKUP_DIR" ] ; then
     AUD_BACKUP_DIR=${COMMON_BACKUP_DIR}
   else
     AUD_BACKUP_DIR=${ADUMP_DEST}
   fi
   echo "Backup archive audit files to ${AUD_BACKUP_DIR}"
   DAILY_AUD_ARCHIVE=${AUD_BACKUP_DIR}/${DBINST}_audit_files_${MYD}.tgz
   if [ -s "${DAILY_AUD_ARCHIVE}" ] ; then
     echo "Renaming ${DAILY_AUD_ARCHIVE}"
     mv ${DAILY_AUD_ARCHIVE} ${DAILY_AUD_ARCHIVE}.`date +%H%M%S`
   fi
   cd ${ADUMP_DEST}
   tar -czf ${DAILY_AUD_ARCHIVE} *.aud >/dev/null 2>&1 && rm -fv ${ADUMP_DEST}/*.aud

   echo "Delete backup archives of tracefiles older than ${KEEP_DAYS} days"
   # Delete archived tracefiles older than ${KEEP_DAYS} days
   find ${BACKUP_DIR} -name '*.tgz' -mtime +${KEEP_DAYS} -exec rm {} \;
   find ${AUD_BACKUP_DIR} -name '*.tgz' -mtime +${KEEP_DAYS} -exec rm {} \;

done

# Recycle listener log
echo "**********************"
echo "Managing the Listener logs"
LISTENER_HOME=$(ps -ef|grep tnslsnr|grep -v grep|grep -v sed | awk '{print $8}' |sort -u | sed 's/\/bin\/tnslsnr//')
if [ -z "$LISTENER_HOME" ] ; then
  echo "No listener running"
else
  export ORACLE_HOME=$LISTENER_HOME
  TRACE_BASE_DIR=$($LISTENER_HOME/bin/lsnrctl show trc_directory | grep trc_directory | sed 's/^[^\/]*//;s/trace//')

  # For XML log files
  echo -n "Clearing Listener XML files in "
  cd ${TRACE_BASE_DIR}alert && pwd
  echo log*.xml | xargs -n1 cp /dev/null
  find $TRACE_BASE_DIR/alert  -name 'log*.xml*' -mtime +1 -exec rm {} \;

  # For listener.log text files
  LISTENER_LOG=${TRACE_BASE_DIR}trace/listener.log
  if [ -n "$COMMON_BACKUP_DIR" ] ; then
    LISTENER_LOG_ARCHIVE=${COMMON_BACKUP_DIR}/listener.log_${MYD}.gz
  else
    LISTENER_LOG_ARCHIVE=${LISTENER_LOG}_${MYD}.gz
  fi
  echo "Archiving ${LISTENER_LOG} to ${LISTENER_LOG_ARCHIVE}"
  if [ -s "${LISTENER_LOG_ARCHIVE}" ] ; then
    echo "Renaming ${LISTENER_LOG_ARCHIVE}"
    mv ${LISTENER_LOG_ARCHIVE} ${LISTENER_LOG_ARCHIVE}.`date +%H%M%S`
  fi
  echo "Backup copy and clear listener log: ${LISTENER_LOG}"
  gzip -c ${LISTENER_LOG} > ${LISTENER_LOG_ARCHIVE} && cat /dev/null > ${LISTENER_LOG}
  echo "Delete listener logs older than ${KEEP_DAYS} days"
  find `dirname ${LISTENER_LOG_ARCHIVE}` -name 'listener*' -mtime +${KEEP_DAYS} -exec rm {} \;
fi

echo "**********************"
echo "Log management process complete at `date`"
echo "**********************"
