# ClonePDB.sh - Clone an existing PDB
# 
# Author: Dennis Heltzel 01/29/2022

LOG_DIR=~/logs
[ -d ${LOG_DIR} ] || mkdir -p ${LOG_DIR}

RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh
REFRESH=FALSE
DBNAME=${ORACLE_PDB_SID:-${ORACLE_SID}}
CONN_STR='sqlplus -s / as sysdba'

usage() {
  echo "Usage: $0 -s source -d destination -r"
  echo "  -s source PDB name - defaults to ${DBNAME}"
  echo "  -d destination PDB name (required)"
  echo "  -r refresh the clone, dropping the destination PDB first if it exists"
  exit 1
}

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

ORACLE_PDB_SID=ORA\$ROOT

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

drop_pdb () {
  tty -s && echo -e "Dropping PDB ${DEST_NAME}.\n<return> to continue, CTRL-C to abort.";read ok
  if is_pdb_open ${DEST_NAME} ; then
    tty -s && echo "PDB ${DEST_NAME} is open, closing . . ."
    (${CONN_STR} <<!
WHENEVER SQLERROR EXIT SQL.SQLCODE
alter session set container = ${DEST_NAME};
shutdown abort
exit
!
) |tee ${LOG_DIR}/STOP_${DEST_NAME}.log
  fi
  tty -s && echo "Dropping PDB ${DEST_NAME} . . ."
  (${CONN_STR} <<!
WHENEVER SQLERROR EXIT SQL.SQLCODE
alter session set container = ORA\$ROOT;
drop pluggable database ${DEST_NAME} including datafiles;
exit
!
) |tee ${LOG_DIR}/DROP_${DEST_NAME}.log
}

clone_pdb () {
  is_pdb_open ${SOURCE_NAME} || exit 1 >/dev/null
  tty -s && echo -e "Cloning ${SOURCE_NAME} to a new PDB called ${DEST_NAME}.\n<return> to continue, CTRL-C to abort.";read ok
(${CONN_STR} <<!
create pluggable database ${DEST_NAME} from ${SOURCE_NAME} storage unlimited tempfile reuse file_name_convert=('/opt/app/oracle/oradata/DEVO/${SOURCE_NAME}', '/opt/app/oracle/oradata/DEVO/${DEST_NAME}');
alter pluggable database ${DEST_NAME} open;
alter pluggable database ${DEST_NAME} save state;
exit
!
) |tee ${LOG_DIR}/Clone_${SOURCE_NAME}_to_${DEST_NAME}.log
}

# Check if the destination exists and if refresh is selected
if pdb_exists ${DEST_NAME} >/dev/null ; then
  if [ ${REFRESH} == "TRUE" ] ; then
    drop_pdb
  else
    tty -s && echo "PDB ${DEST_NAME} exists and refresh option is not selected"
    exit 1
  fi
else
  tty -s && echo "PDB ${DEST_NAME} does not exist"
fi

if is_pdb_open ${SOURCE_NAME} >/dev/null ; then
  clone_pdb
else
  tty -s && echo "PDB ${SOURCE_NAME} is not open"
fi
