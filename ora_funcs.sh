#!/bin/bash
#
# File $Id: save_db_configs.sh 2268 2014-01-15 17:53:20Z dheltzel $
# Modified $Author: dheltzel $
# Date $Date: 2014-01-15 17:53:20 +0000 (Wed, 15 Jan 2014) $
# Revision $Revision: 2268 $

pathmunge () {
  if ! echo $PATH | /bin/egrep -q "(^|:)$1($|:)" ; then
     if [ "$2" = "after" ] ; then
        PATH=$PATH:$1
     else
        PATH=$1:$PATH
     fi
  fi
}

# Sets the Oracle environment, if possible
oe ()
{
  # if no argument, try the existing value of ORACLE_SID
  TMP_ORACLE_SID=${1:-$ORACLE_SID}
  if [ -z "${TMP_ORACLE_SID}" ] ; then
    echo "No SID"
    return 1
  fi
  # Set the SID
  ORACLE_SID=`ps -ef|grep ora_\\\\pmon|sed -e "s/.*pmon_//"|grep -i ${TMP_ORACLE_SID}|sort -u`
  # check that only one SID was found
  if [ `echo $ORACLE_SID|wc -w` -gt 1 ] ; then
    echo "Too many matching SID's (${ORACLE_SID})"
    # Just take the first one
    ORACLE_SID=`echo $ORACLE_SID|cut -d" " -f1`
    echo "Setting ORACLE_SID to $ORACLE_SID"
  fi
  if [ -z "${ORACLE_SID}" ] ; then
    echo "SID not found"
    return 1
  fi
  ps -e -o command,pid | grep ora_\\\\pmon|grep ${ORACLE_SID}|read cmd pid
  #Find ORACLE_HOME from process id
  if [ -r /proc/$pid/exe ] ; then
    TMP_ORACLE_HOME=$(ls -l /proc/$pid/exe | awk -F'> ' '{print $2}' | sed 's/\/[^\/]*\/[^\/]*$//')
  else
    # Get the OH from oratab if the process files are not readable
    TMP_ORACLE_HOME=`grep "${TMP_ORACLE_SID}" /etc/oratab|cut -d: -f2`
    # If it wasn't found, strip off the last char to work on RAC
    if [ -z "${TMP_ORACLE_HOME}" ]; then
      INST=`expr substr ${TMP_ORACLE_SID} ${#TMP_ORACLE_SID} 1`
      TMP_ORACLE_HOME=`grep "${TMP_ORACLE_SID%$INST}" /etc/oratab|cut -d: -f2`
    fi
  fi

  # If we found an OH and it's valid, set the rel OH, otherwise leave it unchanged and hope for the best
  if [ -d "${TMP_ORACLE_HOME}" ] ; then
     ORACLE_HOME=${TMP_ORACLE_HOME}
  fi

  # Check that the ORACLE_SID we finally decided on has a running db
  ps -ef|grep ora_\\pmon_${ORACLE_SID} >/dev/null
  if [ $? = '0' ] ; then
    # Everything works! exit with success
    echo "${ORACLE_SID}"
    export PATH=$ORACLE_HOME/bin:/usr/kerberos/bin:/usr/local/bin:/bin:/usr/bin
    export ORACLE_SID ORACLE_HOME PATH
    return 0
  else
    echo "SID not found"
    return 1
  fi
}

test_connect ()
{
  if [ $# -gt 0 ] ; then
    oe $1
  fi

  # Test the connection
  export DB_ROLE=`sqlplus -s / as sysdba <<!
set pages 0
select DATABASE_ROLE from v\\$database;
exit
!`
  echo $DB_ROLE | grep ORA- && return 1
  return 0
}

is_standby ()
{
  if [ $# -gt 0 ] ; then
    oe $1
  fi

  # Test the connection
  (sqlplus -s / as sysdba <<!
set pages 0
select DATABASE_ROLE from v\\$database;
exit
!
) | grep PRIMARY >/dev/null && return 0
  return 1
}

is_clonedb ()
{
  if [ $# -gt 0 ] ; then
    oe $1
  fi

  # Test the connection
  (sqlplus -s / as sysdba <<!
set pages 0
select VALUE from v\$parameter where NAME = 'clonedb';
exit
!
) | grep TRUE >/dev/null && return 0
  return 1
}

dbname ()
{
  if [ $# -gt 0 ] ; then
    oe $1
  fi

  # Get the real database name
  export DBNAME=`sqlplus -s / as sysdba <<!
set pages 0
select NAME from v\\$database;
exit
!`
  return 0
}

chk_invalid ()
{
sqlplus -s / as sysdba <<!
SET serverout ON
SET FEED OFF
DECLARE
  cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO cnt FROM dba_objects WHERE status <> 'VALID';
  IF cnt > 0 THEN
    dbms_output.put_line(cnt || ' invalid objects, compiling . . .');
    sys.utl_recomp.recomp_serial;
    SELECT COUNT(*) INTO cnt FROM dba_objects WHERE status <> 'VALID';
  END IF;
  dbms_output.put_line(cnt || ' invalid objects');
END;
/
exit
!
}

validate_indexes ()
{
sqlplus -s / as sysdba <<!
set pages 0
set lines 200
set feed off
set head off
prompt set echo on
prompt set feed off
prompt set timi on
prompt set time on
select 'alter index ' || owner || '.' || index_name || ' rebuild nologging online;' from dba_indexes where status = 'UNUSABLE'
union
select 'alter index ' || index_owner || '.' || index_name || ' rebuild partition ' || partition_name || ' nologging online' || ';' from dba_ind_partitions where status = 'UNUSABLE';
exit
!
}
