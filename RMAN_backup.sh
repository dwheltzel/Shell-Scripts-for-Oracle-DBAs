# RMAN_backup.sh - Take rman full backup(incremental level 0 )
# 
# Author: Dennis Heltzel 02/9/2022

LOGDIR=/home/oracle/logs

usage() {
  echo "Usage: $0 [-d db name] [-p PDB name] [-i incremental level] [-t tag name] [-l log directory] [-e] [-c] [-s]"
  echo "  -d container database name - defaults to ${ORACLE_SID}"
  echo "  -p PDB to backup - defaults to entire container"
  echo "  -l incremental level - if left off, a full, non-incremental backup is performed"
  echo "  -t tag name"
  echo "  -l log directory - defaults to ${LOGDIR}"
  echo "  -e - only cleanup expired or missing files (always done before any backup)"
  echo "  -c - prints the RMAN configuration and exits"
  echo "  -s - sets the RMAN configuration and exits"
  exit 1
}

CDBNAME=${ORACLE_SID}
PDBNAME=${ORACLE_PDB_SID}
CONN_STR='sqlplus -s / as sysdba'
RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh
export PATH=$PATH:$ORACLE_HOME/bin
LEVEL=
TAGNAME=
CROSSCHECK_ONLY=
SHOW_CFG=
SET_CFG=
#START_DATE=`date '+%Y%m%d%H%M'`
RMAN_DATE=$(date +%y-%m-%d_%H%M%S)

# Handle parameters
while getopts "d:p:i:t:l:ecs" opt; do
  case $opt in
    d)
      CDBNAME=$OPTARG
      ;;
    p)
      PDBNAME=$OPTARG
      ;;
    i)
      LEVEL=$OPTARG
      ;;
    t)
      TAGNAME=$OPTARG
      ;;
    l)
      LOGDIR=$OPTARG
      ;;
    e)
      CROSSCHECK_ONLY=YES
      ;;
    c)
      SHOW_CFG=YES
      ;;
    s)
      SET_CFG=YES
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

oe ${CDBNAME}
# Set tagname
if [ -z ${TAGNAME} ] ; then
  if [ -z ${LEVEL} ] ; then
    TAGNAME=FULL_${RMAN_DATE}
  else
    TAGNAME=INCR_${LEVEL}_${RMAN_DATE}
  fi 
fi
LOGFILE=${LOGDIR}/RMAN_${TAGNAME}.log

#RMANBACKUP_MOUNTPOINT1=/u01/oracle/rman_bkp
#PARALLELISM=4
#MAXPIECESIZE=3g
#export ORACLE_HOME=/u01/app/oracle/product/12.1.0/dbhome_1
#export ORACLE_SID=TESTDB
#export PATH=$ORACLE_HOME/bin:$PATH

showConfig () {
  rman <<!
connect target /
show all;
exit
!
}

#SELECT OPERATION, STATUS, MBYTES_PROCESSED, START_TIME, END_TIME from Vi\$RMAN_STATUS;

#configure controlfile autobackup format for device type disk to '$RMANBACKUP_MOUNTPOINT1/%F';
#configure device type disk parallelism $PARALLELISM;
setConfig () {
  rman <<!
connect target /
set echo on;
configure retention policy to recovery window of 7 days;
configure backup optimization on;
configure controlfile autobackup on;
configure maxsetsize to unlimited;
show all;
exit
!
}

crosscheck () {
  (rman <<!
connect target /
set echo on;
crosscheck archivelog all;
crosscheck backup;
delete noprompt obsolete;
exit
!
) > ${LOGDIR}/RMAN_${TAGNAME}-delete.log
}

incrLevel () {
  (rman <<!
connect target /
set echo on;
backup as compressed backupset tag '${TAGNAME}' incremental level ${LEVEL} database plus archivelog;
sql 'alter system archive log current';
exit
!
) > ${LOGFILE}
}

full_backup () {
  (rman <<!
connect target /
set echo on;
backup as compressed backupset tag '${TAGNAME}' database plus archivelog;
sql 'alter system archive log current';
exit
!
) > ${LOGFILE}
}

# Main logic

# Show and/or set the config params (only needed for new databases
if [ "${SHOW_CFG}" == 'YES' ] ; then
  showConfig
  exit 0
fi
if [ "${SET_CFG}" == 'YES' ] ; then
  setConfig
  exit 0
fi
# If CROSSCHECK_ONLY=YES, exit afterwards
if [ "${CROSSCHECK_ONLY}" == 'YES' ] ; then
  crosscheck
  exit 0
fi

# Crosscheck and purge any obsolete backup pieces - this prevents error messages later
tty -s && echo "Performing crosscheck and deleting missing or obsolete backup pieces"
crosscheck

# Perform actual backup
if [ -z ${LEVEL} ] ; then
  tty -s && echo "Performing a full backup . . ."
  full_backup
else
  tty -s && echo "Performing an incremental ${LEVEL} backup . . ."
  incrLevel ${LEVEL}
fi
