# rman_full_bkp.sh - Take rman full backup(incremental level 0 )
# 
# Author: Dennis Heltzel 02/9/2022

LOGDIR=/home/oracle/logs

usage() {
  echo "Usage: $0 [-d db name] [-p PDB name] [-i incremental level] [-t tag name] [-l log directory] [-c] [-s]"
  echo "  -d container database name - defaults to ${ORACLE_SID}"
  echo "  -p PDB to backup - defaults to entire container"
  echo "  -l incremental level - if left off, a full, non-incremental backup is performed"
  echo "  -t tag name"
  echo "  -l log directory - defaults to ${LOGDIR}"
  echo "  -c - prints the RMAN configuration and exits"
  echo "  -s - sets the RMAN configuration and exits"
  exit 1
}

CDBNAME=${ORACLE_SID}
PDBNAME=${ORACLE_PDB_SID}
CONN_STR='sqlplus -s / as sysdba'
RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh
LEVEL=
TAGNAME=
SHOW_CFG=
SET_CFG=
#START_DATE=`date '+%Y%m%d%H%M'`
RMAN_DATE=$(date +%y-%m-%d_%H%M%S)

# Handle parameters
while getopts "d:p:i:t:l:cs" opt; do
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
  rman << EOF
connect target /
show all;
exit
EOF
}

#SELECT OPERATION, STATUS, MBYTES_PROCESSED, START_TIME, END_TIME from Vi\$RMAN_STATUS;

#configure controlfile autobackup format for device type disk to '$RMANBACKUP_MOUNTPOINT1/%F';
#configure device type disk parallelism $PARALLELISM;
setConfig () {
  rman << EOF
connect target /
set echo on;
configure retention policy to recovery window of 7 days;
configure backup optimization on;
configure controlfile autobackup on;
configure maxsetsize to unlimited;
show all;
exit
EOF
}

crosscheck () {
  rman log= ${LOGDIR}/RMAN_${TAGNAME}-delete.log << EOF
connect target /
set echo on;
crosscheck archivelog all;
crosscheck backup;
delete noprompt obsolete;
exit
EOF
}

incrLevel () {
  rman log=${LOGFILE} << EOF
connect target /
set echo on;
backup as compressed backupset tag '${TAGNAME}' incremental level ${LEVEL} database plus archivelog;
sql 'alter system archive log current';
exit
EOF
}

full_backup () {
  rman log=${LOGFILE} << EOF
connect target /
set echo on;
backup as compressed backupset tag '${TAGNAME}' database plus archivelog;
sql 'alter system archive log current';
exit
EOF
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

# Crosscheck and purge any obsolete backup pieces - this prevents error messages later
crosscheck
exit

# Perform actual backup
if [ -z ${LEVEL} ] ;
  full_backup
else
  incrLevel ${LEVEL}
fi
