# ClonePDB.sh - Clone an existing PDB
# 
# Author: Dennis Heltzel 01/29/2022

usage() {
  echo "Usage: $0 -s source -d destination -r"
  echo "  -s source PDB name - defaults to ${DBNAME}"
  echo "  -d destination PDB name (required)"
  echo "  -r refresh the clone, dropping the destination PDB first if it exists"
  exit 1
}

DBNAME=${ORACLE_PDB_SID:-${ORACLE_SID}}
CONN_STR='sqlplus -s / as sysdba'
RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh
REFRESH=FALSE

# Handle parameters
while getopts "s:d:r" opt; do
  case $opt in
    s)
      SOURCE_NAME=$OPTARG
      ;;
    d)
      DEST_NAME=$OPTARG
      ;;
    r)
      REFRESH=TRUE
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

WORK_DIR=${WORK_DIR:-`pwd`}
ORACLE_PDB_SID=ORA\$ROOT
SOURCE_OPEN=`is_pdb_open ${SOURCE_NAME} >/dev/null`
DEST_EXISTS=`pdb_exists ${DEST_NAME} >/dev/null`

# Check that source and dest are different
if [ ${SOURCE_NAME} == ${DEST_NAME} ] ; then
  tty -s && echo "Source and destination cannot be the same"
  exit 1
fi
# Check that source is a valid PDB
if [ ${SOURCE_NAME} == "ORA\$ROOT" ] || [ ${SOURCE_NAME} == "PDB\$SEED" ] ; then
  tty -s && echo "Cannot clone from ${SOURCE_NAME}"
  exit 1
fi
# Check that destination is a valid PDB
if [ ${DEST_NAME} == "ORA\$ROOT" ] || [ ${DEST_NAME} == "PDB\$SEED" ] ; then
  tty -s && echo "Cannot clone to ${DEST_NAME}"
  exit 1
fi

#if pdb_exists ${SOURCE_NAME} >/dev/null ; then
#  tty -s && echo "${SOURCE_NAME} is a valid PDB"
#fi
#if ${SOURCE_OPEN} ; then
#  tty -s && echo "PDB ${SOURCE_NAME} is open"
#fi

# Check if the destination exists and if refresh is selected
if pdb_exists ${DEST_NAME} >/dev/null ; then
  if [ ${REFRESH} == "TRUE" ] ; then
    tty -s && echo -e "Dropping PDB ${DEST_NAME}.\n<return> to continue, CTRL-C to abort.";read ok
    (${CONN_STR} <<!
prompt set echo on;
prompt set time on;
prompt set timi on;
alter pluggable database ${DEST_NAME} close;
drop pluggable database ${DEST_NAME} including datafiles;
exit
!
) |tee ${WORK_DIR}/DROP_${DEST_NAME}.log
  else
    tty -s && echo "PDB ${DEST_NAME} exists and refresh option is not selected"
    exit 1
  fi
else
  tty -s && echo "PDB ${DEST_NAME} does not exist"
fi

if is_pdb_open ${SOURCE_NAME} >/dev/null ; then
  tty -s && echo -e "Cloning ${SOURCE_NAME} to a new PDB called ${DEST_NAME}.\n<return> to continue, CTRL-C to abort.";read ok
(${CONN_STR} <<!
prompt set echo on;
prompt set time on;
prompt set timi on;
create pluggable database ${DEST_NAME} from ${SOURCE_NAME} storage unlimited tempfile reuse file_name_convert=('/opt/app/oracle/oradata/DEVO/${SOURCE_NAME}', '/opt/app/oracle/oradata/DEVO/${DEST_NAME}');
alter pluggable database ${DEST_NAME} open;
alter pluggable database ${DEST_NAME} save state;
exit
!
) |tee ${WORK_DIR}/Clone_${SOURCE_NAME}_to_${DEST_NAME}.log

else
  tty -s && echo "PDB ${SOURCE_NAME} is not open"
fi
