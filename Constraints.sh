# Constraints.sh - Create DDL to disable and re-enable all constraints for a schema
# 
# Author: Dennis Heltzel 01/24/2022

usage() {
  echo "Usage: $0 -s schema"
  echo "  -d database name - defaults to ${DBNAME}"
  echo "  -s schema (required) name of the schema to process"
  exit 1
}

DBNAME=${ORACLE_PDB_SID:-${ORACLE_SID}}
CONN_STR='sqlplus -s / as sysdba'
RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh

# Handle parameters
while getopts ":d:s:" opt; do
  case $opt in
    d)
      DBNAME=$OPTARG
      ;;
    s)
      SCHEMA=$OPTARG
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
DISABLE_FILE=${WORK_DIR}/disable_${DBNAME}_${SCHEMA}.ddl
ENABLE_FILE=${WORK_DIR}/enable_${DBNAME}_${SCHEMA}.ddl
ORACLE_PDB_SID=${DBNAME}
#CONS_STATUS=" and status = 'ENABLED'"
CONS_STATUS=" "
#echo "DBNAME=${DBNAME}:ORACLE_SID=${ORACLE_SID}:ORACLE_PDB_SID=${ORACLE_PDB_SID}"

tty -s && echo "Generating list of constraint disable commands from ${SCHEMA} in ${ORACLE_PDB_SID}: ${DISABLE_FILE}"
(${CONN_STR} <<!
set pages 0
set feed off
set head off
set lines 180
prompt set sqlprompt "_CONNECT_IDENTIFIER> ";
prompt set feed off;
prompt set echo on;
prompt set time on;
prompt set timi on;
prompt spool ${WORK_FILE}
SELECT 'alter table '||owner||'."'||table_name||'" disable constraint '||constraint_name||';' disable_cmd
  FROM dba_constraints WHERE owner = '${SCHEMA}'${CONS_STATUS};
exit
!
) > ${DISABLE_FILE}

tty -s && echo "Generating list of constraint enable commands from ${SCHEMA} in ${ORACLE_PDB_SID}: ${ENABLE_FILE}"
(${CONN_STR} <<!
set pages 0
set feed off
set head off
set lines 180
prompt set sqlprompt "_CONNECT_IDENTIFIER> ";
prompt set feed off;
prompt set echo on;
prompt set time on;
prompt set timi on;
prompt spool ${WORK_FILE}
SELECT 'alter table '|| owner||'.'||table_name||' enable constraint '||constraint_name||';' enable_cmd
  FROM dba_constraints WHERE owner = '${SCHEMA}'${CONS_STATUS};
exit
!
) > ${ENABLE_FILE}


