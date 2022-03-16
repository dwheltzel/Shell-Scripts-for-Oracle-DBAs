#!/bin/bash
# DatafileShrink.sh - Shrinks the sizes of datafiles to release space.
#
# Author: Dennis Heltzel

RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh
DBNAME=${ORACLE_PDB_SID:-${ORACLE_SID}}
CONN_STR='sqlplus -s / as sysdba'
RUN_DDL=Y
BASEDIR=~/logs

usage() {
  echo "Usage: $0 [-n] [-p] [-d database name] [-b base dir]"
  echo "  -n - no changes, just create the files with the shrink commands"
  echo "  -p - purge the dba_recyclebin"
  echo "  -d database name - defaults to ${DBNAME}"
  echo "  -b base dir - the base directory used to hold all generated files (default is ${BASEDIR})"
  exit 1
}

# Handle parameters
while getopts ":npd:b:" opt; do
  case $opt in
    n)
      RUN_DDL=N
      ;;
    p)
      PURGE=Y
      ;;
    d)
      DBNAME=$OPTARG
      ;;
    b)
      BASEDIR=$OPTARG
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

ORACLE_PDB_SID=${DBNAME}
BASE_NAME=${BASEDIR}/DatafileShrink_${DBNAME}-`date "+%y%m%d%H%M"`
REPORT_NAME=${BASE_NAME}.lst
SQL_NAME=${BASE_NAME}.sql
CMD_OUTPUT_NAME=${BASE_NAME}.out
STATS_FILE_NAME=${BASE_NAME}.stats
tty -s && echo "DBNAME: ${DBNAME}"
tty -s && echo "REPORT_NAME: ${REPORT_NAME}"
tty -s && echo "SQL_NAME: ${SQL_NAME}"

# Check the flashback status of the database
FB_ISSUE=`${CONN_STR} <<!
set pages 0
set feed off
SET serverout ON SIZE UNLIMITED
DECLARE
  fl_status VARCHAR2(30);
  cnt       PLS_INTEGER := 1;
BEGIN
  SELECT flashback_on INTO fl_status FROM v\\\$database;
  IF (fl_status = 'RESTORE POINT ONLY') THEN
    SELECT COUNT(*) INTO cnt FROM v\\\$restore_point;
  END IF;
  IF (fl_status = 'NO' OR cnt = 0) THEN
    dbms_output.put_line('N');
  ELSE
    dbms_output.put_line('Y');
  END IF;
END;
/
exit
!`
if [ "${FB_ISSUE}" = 'Y' ] ; then
  tty -s && echo "Flashback active - aborting shrink"
  exit 1
fi

# Is this a clone db?
CLONE_DB=`${CONN_STR} <<!
set pages 0
select value from v\\\$parameter where NAME = 'clonedb';
exit
!`
if [ "${CLONE_DB}" = "TRUE" ] ; then
  tty -s && echo "This is a clonedb - aborting shrink"
  exit 1
fi


# Get the database block size
BLOCK_SIZE=`${CONN_STR} <<!
set pages 0
select value from v\\\$parameter where NAME = 'db_block_size';
exit
!`

NEXT_EXT=10M
tty -s && echo "BLOCK_SIZE:${BLOCK_SIZE}:"
if [ "${BLOCK_SIZE}" -gt 8192 ] ; then
  NEXT_EXT=20M
fi
tty -s && echo "NEXT_EXT:${NEXT_EXT}:"

# Purge the recyclebin if asked
if [ "${PURGE}" = 'Y' ] ; then
  tty -s && echo "Purging the DBA Recyclebin . . ."
  ${CONN_STR} <<!
purge dba_recyclebin;
exit
!
fi

# Fix any datafiles that are not autoextensible or have small next extents
${CONN_STR} <<!
set ver off
set pages 200
set feed off
set head off
set lines 250
set trimspool on
spool ${SQL_NAME}
select 'alter database datafile ''' || file_name || ''' autoextend on maxsize unlimited;' fix_cmd
  from dba_data_files where (maxbytes < 34359721984 OR autoextensible = 'NO') AND tablespace_name NOT LIKE 'UNDO%' AND tablespace_name NOT LIKE 'SYS%';
select 'alter database datafile ''' || file_name || ''' autoextend on next ${NEXT_EXT};' fix_cmd
  from dba_data_files where increment_by < 1280  AND tablespace_name NOT LIKE 'UNDO%' AND tablespace_name NOT LIKE 'SYS%';
spool off
exit
!
# Run DDL if requested
if [ "${RUN_DDL}" = "Y" ] ; then
  echo "exit" >>${SQL_NAME}
  ${CONN_STR} @${SQL_NAME} >${CMD_OUTPUT_NAME}
fi

# Get the size of the datafiles before shrinking
PRE_SHRINK_SIZE=`${CONN_STR} <<!
set pages 0
SELECT SUM(bytes) / 1024 / 1024 FROM dba_data_files WHERE tablespace_name NOT LIKE 'UNDO%' AND tablespace_name NOT LIKE 'SYS%';
exit
!`

# Run the report
${CONN_STR} <<!
set ver off
set pages 200
set feed off
set lines 250
set trimspool on
spool ${REPORT_NAME}
prompt Current size
SELECT SUM(bytes) / 1024 / 1024 datafile_size_mb, SUM(bytes) / 1024 / 1024 / 1024 datafile_size_gb FROM dba_data_files WHERE tablespace_name NOT LIKE 'UNDO%' AND tablespace_name NOT LIKE 'SYS%';
prompt .
prompt Recyclebin size
SELECT SUM(space) / 128 recoverable_mb, 'purge dba_recyclebin;' cmd FROM dba_recyclebin;
prompt .
prompt datafiles that are not set to autoextend to max size
select file_name, autoextensible, maxbytes, 'alter database datafile ''' || file_name || ''' autoextend on maxsize unlimited;' fix_cmd
  from dba_data_files where (maxbytes < 34359721984 OR autoextensible = 'NO') AND tablespace_name NOT LIKE 'UNDO%' AND tablespace_name NOT LIKE 'SYS%';
prompt .
prompt datafiles that have small increment by size < ${NEXT_EXT}
select file_name, increment_by / 128 NEXT_MB, 'alter database datafile ''' || file_name || ''' autoextend on next ${NEXT_EXT};' fix_cmd
  from dba_data_files where increment_by < 128  AND tablespace_name NOT LIKE 'UNDO%' AND tablespace_name NOT LIKE 'SYS%';
prompt .
prompt datafiles that can be resized
select bytes / 1024 / 1024 real_size,
 ceil((nvl(hwm, 1) * ${BLOCK_SIZE}) / 1024 / 1024) + 9 shrinked_size,
 bytes / 1024 / 1024 - (ceil((nvl(hwm, 1) * ${BLOCK_SIZE}) / 1024 / 1024) + 9) released_size,
 'alter database datafile ' || '''' || file_name || '''' || ' resize ' || to_char(ceil((nvl(hwm, 1) * ${BLOCK_SIZE}) / 1024 / 1024)+9) || ' m;' cmd
  from dba_data_files a, (select file_id, max(block_id + blocks - 1) hwm from dba_extents group by file_id) b
where a.file_id = b.file_id(+) and ceil(blocks * 8 / 1024) - ceil((nvl(hwm, 1) * ${BLOCK_SIZE}) / 1024 / 1024) > 10
 AND tablespace_name NOT LIKE 'UNDO%' AND tablespace_name NOT LIKE 'SYS%';

SET serverout ON SIZE UNLIMITED
DECLARE
  fl_status VARCHAR2(30);
  cnt       PLS_INTEGER := 1;
BEGIN
  SELECT flashback_on INTO fl_status FROM v\$database;
  IF (fl_status = 'RESTORE POINT ONLY') THEN
    SELECT COUNT(*) INTO cnt FROM v\$restore_point;
  END IF;
  IF (fl_status = 'NO' OR cnt = 0) THEN
    dbms_output.put_line('No FB issues');
  ELSE
    dbms_output.put_line('FB issue - do not shrink datafiles');
  END IF;
END;
/
spool off
exit
!

# Run DDL if requested
if [ "${RUN_DDL}" = "Y" ] ; then
  grep alter ${REPORT_NAME} > ${SQL_NAME}
  echo "exit" >>${SQL_NAME}
  ${CONN_STR} @${SQL_NAME} >>${CMD_OUTPUT_NAME}

  # Get the size of the datafiles after shrinking
  POST_SHRINK_SIZE=`${CONN_STR} <<!
set pages 0
SELECT SUM(bytes) / 1024 / 1024 FROM dba_data_files WHERE tablespace_name NOT LIKE 'UNDO%' AND tablespace_name NOT LIKE 'SYS%';
exit
!`
  tty -s && echo "Database: ${DB_NAME}  Shrink Date: `date`" >${STATS_FILE_NAME}
  tty -s && echo "Starting size: ${PRE_SHRINK_SIZE}|" >>${STATS_FILE_NAME}
  tty -s && echo "Ending size: ${POST_SHRINK_SIZE}|" >>${STATS_FILE_NAME}
  RECOVERED_SIZE=$(($PRE_SHRINK_SIZE - $POST_SHRINK_SIZE))
  tty -s && echo "Disk space recovered (MB): ${RECOVERED_SIZE}" >>${STATS_FILE_NAME}
  cat ${STATS_FILE_NAME}
fi
