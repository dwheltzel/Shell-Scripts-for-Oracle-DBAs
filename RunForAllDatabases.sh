# Iterates a command across all running DB instances 
#
# File $Id: RunForAllDatabases.sh 3857 2014-04-09 14:22:53Z dheltzel $
# Modified $Author: dheltzel $ 
# Date $Date: 2014-04-09 10:22:53 -0400 (Wed, 09 Apr 2014) $
# Revision $Revision: 3857 $
. `dirname "${BASH_SOURCE[0]}"`/ora_funcs.sh

RUN_CMDS=Y

usage() {
  echo "Usage: $0 -c command string [-n ] [-e exclude type] [-l list file]"
  echo "  -c command string - the string of commands to run once the DB environment is set"
  echo "  -n - no changes, only create files with commands to run, so you can edit and run manually"
  echo "  -e exclude type - exclude these types of databases: clonedb standby"
  echo "  -l list file - name of text file that lists the databases to process, 1 per line"
  exit 1
}

# Handle parameters
while getopts ":c:e:l:n" opt; do
  case $opt in
    n)
      RUN_CMDS=N
      ;;
    c)
      CMD_STRING=$OPTARG
      ;;
    l)
      LIST_FILE=$OPTARG
      ;;
    e)
      EXCLUDE_TYPE=$OPTARG
      echo "Exclude: $EXCLUDE_TYPE"
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

REPORT_NAME=RunForAllDatabases-`date "+%y%m%d%H%M"`.sh
:>${REPORT_NAME}
# Create the file listing all the databases to operate on
if [ -z ${LIST_FILE} ] ; then
  LIST_FILE=/tmp/Run4All-listing.txt
  ps -ef|grep ora_\\pmon|cut -d_ -f3-|grep -v ASM > $LIST_FILE
fi
#echo "List file: $LIST_FILE"

for ORACLE_SID in `cat $LIST_FILE`
do
  if [ "$EXCLUDE_TYPE" = "clonedb" ] ; then
    is_clonedb ${ORACLE_SID} && continue
  else
    test_connect ${ORACLE_SID} || continue
  fi

  if [ "$EXCLUDE_TYPE" = "standby" -a "${DB_ROLE}" = "PHYSICAL STANDBY" ] ; then
    continue
  fi

  echo "export ORACLE_SID=${ORACLE_SID};export ORACLE_HOME=${ORACLE_HOME};${CMD_STRING}" >>${REPORT_NAME}
done

echo "Commands written to ${REPORT_NAME}"

if [ "${RUN_CMDS}" = 'Y' ] ; then
  sh ${REPORT_NAME}
fi

# cleanup
if [ -r "/tmp/Run4All-listing.txt" ] ; then
  rm /tmp/Run4All-listing.txt
fi
