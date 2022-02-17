# Cleanup of filesystems by the root user
# 
# Author: Dennis Heltzel 02/15/2022

LOGDIR=/home/oracle/logs
export ORACLE_HOME=/opt/app/oracle/19c
DIAGDIR=/opt/app/oracle/diag/rdbms
RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh

usage() {
  echo "Usage: $0 [-i]"
  echo "  -l - interactive run"
  exit 1
}

RUN_DATE=$(date +%y-%m-%d_%H%M%S)

# Handle parameters
while getopts "d:p:i:t:l:cs" opt; do
  case $opt in
    i)
      INTERACTIVE=YES
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

LOGFILE=${LOGDIR}/RMAN_${TAGNAME}.log

if [ "${USER}" == "root" ] ; then
  # First, cleanup system files
  journalctl --vacuum-time=1s

  # Remove un-needed system files
  #rm -rf /tmp/OraInstall*
  rm -f /var/log/*.1
  rm -f /var/log/*-20*
  rm -f /var/log/*gz
  # Clear the ones we do need to keep
  #:> /var/spool/mail/root
  #:> /var/log/rdbmsaudit.log
  #:> /var/log/asmaudit.log
fi

## Oracle file cleanup

# Migrate schemas before we run purgelogs
ADR_HOME=`ls -d ${DIAGDIR}/*/${ORACLE_SID}|cut -c17-`
tty -s && echo $ADR_HOME
${ORACLE_HOME}/bin/adrci exec="set homepath $ADR_HOME; migrate schema"
# Fix permissions - If these pv dirs are owned by root, you can't login locally
#chown -R oracle /opt/app/oracle/diag/rdbms/*/*/metadata_pv

if [ -x purgeLogs ] ; then
  purgeLogs -orcl 1 -osw 1 -oda 1 -extra /tmp:1,/var/log:1
fi

cd $DIAGDIR

# remove core dumps
rm -rf ${DIAGDIR}/*/*/trace/cdmp*
find /opt/app -name "cdmp*" -type d -delete

# remove incident files
rm -rf ${DIAGDIR}/*/*/incident/incdir*

DIAGDIR=/opt/app

# remove audit files
find /opt/app -mount -name "*.aud" -type f -delete

# remove zero length files older than 6 hours
find $DIAGDIR -mount -name "*.trc" -type f -size 0 -mmin +360 -delete
find $DIAGDIR -mount -name "*.trm" -type f -size 0 -mmin +360 -delete

# clear older trace files
find $DIAGDIR -mount -name "*.trc" -type f -size +0 -mmin +10 -execdir cp /dev/null {} \;
find $DIAGDIR -mount -name "*.trm" -type f -size +0 -mmin +10 -execdir cp /dev/null {} \;

# Clear of all large trace files
#find $DIAGDIR -mount -name "*.trc" -type f -size +0 -execdir cp /dev/null {} \;
#find $DIAGDIR -mount -name "*.trm" -type f -size +0 -execdir cp /dev/null {} \;

# Check ownership of directories
ls -ld /opt/app/oracle/diag/rdbms/*/*/metadata_pv

