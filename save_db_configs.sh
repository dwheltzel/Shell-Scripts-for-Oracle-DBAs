#!/bin/bash
# save_db_configs.sh 
# Author: dheltzel

usage() {
  echo "Usage: $0 [-d database] [-g gather_proc]"
  echo "  -d database - database to process (default is all running instances)"
  echo "  -g gather_type - what type of information to gather (default is all uncommented types listed below)"
  echo "List of valid types:"
  grep "     .g\ather" $0|sed -e "s/gather_/ /"
  echo
  exit 1
}

# Handle parameters
while getopts ":d:g:" opt; do
  case $opt in
    d)
      DB2PROCESS=$OPTARG
      ;;
    g)
      PROCNAME=gather_$OPTARG
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

export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/12.1.0.2/DbHome_2
export ORACLE_SID=FTSPRDWDP1
export PATH=$ORACLE_HOME/bin:$PATH:$HOME/bin

RUNDIR=`dirname "${BASH_SOURCE[0]}"`
. ${RUNDIR}/ora_funcs.sh
EXCLUDE_SCHEMAS="'CSMIG','ORDDATA','ORDPLUGINS','SI_INFORMTN_SCHEMA','XS\$NULL','ANONYMOUS','MDDATA','MGMT_VIEW','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','DBSNMP','DIP','OPS\$ORACLE','ORACLE_OCM','OUTLN','ORACLE','XDB','PERFSTAT','SCOTT','FLOWS_FILES'"
BASEDIR=/cloudfs/saved_configs

gather_lic() {
  # License usage
  tty -s && echo "License info: ${BASEDIR}/config/`hostname -s`/lic-${ORACLE_SID}.lst"
  sqlplus -s / as sysdba @${RUNDIR}/db_option_usage.sql > ${BASEDIR}/config/`hostname -s`/lic-${ORACLE_SID}.lst
}

gather_pfile() {
  # Contents of the spfile
  export PFILE_NAME=${BASEDIR}/config/`hostname -s`/pfile${ORACLE_SID}.ora
  tty -s && echo "RDBMS parameters (pfile): $PFILE_NAME"
  sqlplus -s / as sysdba <<! >/dev/null
create pfile='${PFILE_NAME}' from spfile;
exit
!
}

gather_config() {
  # DB config details
  export ORACFG_NAME=${BASEDIR}/config/`hostname -s`/config-${ORACLE_SID}.lst
  tty -s && echo "Oracle configuration: $ORACFG_NAME"
  (sqlplus -s / as sysdba <<!
set ver off
set lines 150
set pages 500

col comments for a35
col created for a10
col db_unique_name for a15
col database_role for a15
col edition for a20
col edition_name for a20
col last_deploy for a11
col log_mode for a16
col open_mode for a16
col machine for a40
col name for a15
col objects for 999,999
col osuser for a15
col primary_db_unique_name for a15
col status for a10
col usable for a6
col username for a15
col "SERVICE NAME" for a12
col goal for a8
col ACTION_TIME for A30
col ACTION for A20
col NAMESPACE for A10
col VERSION for A10
--col ID for A30
col BUNDLE_SERIES for A10
col COMMENTS for A30


-- basic db info
set head off
select * from v\$version where banner like 'Oracle%';
select 'spfile location: ' || value from v\$parameter where name = 'spfile';
set head on
select dbid, name, db_unique_name, created, log_mode, open_mode, database_role, primary_db_unique_name from v\$database;

-- latest PSU applied to DB
select * from dba_registry_history order by 1;
--select 'Last patch applied: '||comments PSU from (select comments from dba_registry_history where namespace = 'SERVER' and bundle_series = 'PSU' order by id desc) where rownum < 2;

SET HEAD OFF
-- CPU counts for licensing
select 'License CPU count: '||to_char(value / 4)||' on host: '||sys_context('USERENV','SERVER_HOST') "CPU counts for licensing" from v\$parameter where name like 'cpu_count';
select 'SQL Profiles: '||count(*) "SQL Profile counts" from dba_sql_profiles;

-- Directories
SELECT 'Directory: '||owner||'.'||directory_name||' '||directory_path "Directories" FROM dba_directories;

-- Default edition
--select 'Default Edition: '|| edition_name from dba_editions e
--  join database_properties dp on (dp.property_name = 'DEFAULT_EDITION' and dp.property_value = e.edition_name);

-- edition info
--set head on
--prompt Show all the editions now in the DB
--select 'Edition: '||edition_name, level deploy_order, p.privilege usable
-- from dba_editions e left outer join dba_tab_privs p on (e.edition_name = p.table_name and p.privilege = 'USE')
-- start with edition_name = 'ORA\$BASE' connect by prior edition_name = parent_edition_name;

--SELECT 'Service ' || NAME || ' Edition ' || nvl(edition, '(default)') "Service Edition Mapping" FROM dba_services WHERE NAME NOT LIKE 'SYS%' AND NAME NOT LIKE '%XDB' ORDER BY edition, NAME;

--prompt Edition object counts by status
--select o.edition_name, c.comments, max(o.created) last_deploy, count(o.edition_name) objects, o.status
-- from dba_objects_ae o join dba_edition_comments c on (c.edition_name = o.edition_name)
-- join (select edition_name, level deploy_order from dba_editions
--   start with edition_name = 'ORA\$BASE' connect by prior edition_name = parent_edition_name) e on (o.edition_name = e.edition_name)
-- where o.object_type not in ('SYNONYM') group by o.edition_name, c.comments, o.status order by max(e.deploy_order);

exit
!
) > ${ORACFG_NAME}
env|grep ORA >> ${ORACFG_NAME}
dbname ${ORACLE_SID}
tty -s && echo "Cluster Ready Services" >> ${ORACFG_NAME}
srvctl status service -d ${DBNAME} >> ${ORACFG_NAME}
tty -s && echo "CRS DB config settings" >> ${ORACFG_NAME}
srvctl config database -d ${DBNAME} >> ${ORACFG_NAME}
}

gather_users() {
  # List of users
  export USERLIST_NAME=${BASEDIR}/config/`hostname -s`/users-${ORACLE_SID}.lst
  tty -s && echo "User account listing: $USERLIST_NAME"
  (sqlplus -s / as sysdba <<!
set ver off
set lines 500
set pages 500
col USERNAME for a24
col ACCOUNT_STATUS for a18
col LOCK_DATE for a10
col EXPIRY_DATE for a10
col DEFAULT_TABLESPACE for a18
col TEMPORARY_TABLESPACE for a10
col CREATED for a10
col PROFILE for a20
col INITIAL_RSRC_CONSUMER_GROUP for a30
col PASSWORD_VERSIONS for a8
col EDITIONS_ENABLED for a1
col AUTHENTICATION_TYPE for a8

SELECT username, account_status, lock_date, expiry_date, default_tablespace, temporary_tablespace, created,
  profile, initial_rsrc_consumer_group, password_versions, editions_enabled, authentication_type FROM dba_users ORDER BY 1;
exit
!
) > ${USERLIST_NAME}
}

gather_expiring() {
  export EXPIREUSER_NAME=${BASEDIR}/config/`hostname -s`/expiring-${ORACLE_SID}.lst
  tty -s && echo "Expiring Users listing: $EXPIREUSER_NAME"
  (sqlplus -s / as sysdba <<!
set ver off
set lines 100
set pages 500
set head off
set feed off
col USERNAME for a24
col ACCOUNT_STATUS for a18
col LOCK_DATE for a10
col EXPIRY_DATE for a10
SELECT username, account_status, lock_date, expiry_date FROM dba_users WHERE expiry_date IS NOT NULL AND username NOT LIKe '%SYS%' AND username NOT IN (${EXCLUDE_SCHEMAS}) ORDER BY 1;
EXIT
!
) > ${EXPIREUSER_NAME}
}

gather_segments() {
  # List of segments
  export SEGMENTLIST_NAME=${BASEDIR}/config/`hostname -s`/segments-${ORACLE_SID}.lst
  tty -s && echo "Segment listing: $SEGMENTLIST_NAME"
  (sqlplus -s / as sysdba <<!
set ver off
set feed off
set head off
set lines 100
set pages 0
SELECT DISTINCT owner||'.'||segment_name||','||segment_type||','||tablespace_name FROM dba_segments
 WHERE segment_name NOT LIKE 'BIN%' AND segment_name NOT LIKE 'SYS%'
   AND owner NOT LIKE '%SYS%' AND owner NOT LIKE 'APEX%' AND owner NOT IN (${EXCLUDE_SCHEMAS}) ORDER BY 1;
EXIT
!
) > ${SEGMENTLIST_NAME}
}

gather_objects() {
  # List of objects
  export OBJECTLIST_NAME=${BASEDIR}/config/`hostname -s`/objects-${ORACLE_SID}.lst
  tty -s && echo "Object listing: $OBJECTLIST_NAME"
  (sqlplus -s / as sysdba <<!
set ver off
set feed off
set head off
set lines 100
set pages 0
SELECT DISTINCT owner||'.'||object_name||','||object_type||','||status FROM dba_objects WHERE object_name NOT LIKE 'BIN%'
AND owner NOT LIKE '%SYS%' AND owner NOT IN (${EXCLUDE_SCHEMAS}) ORDER BY 1;
EXIT
!
) > ${OBJECTLIST_NAME}
}

gather_columns() {
  # List of columns
  export COLUMNLIST_NAME=${BASEDIR}/config/`hostname -s`/columns-${ORACLE_SID}.lst
  tty -s && echo "Column listing: $COLUMNLIST_NAME"
  (sqlplus -s / as sysdba <<!
set ver off
set feed off
set head off
set lines 150
set pages 0
SELECT 'Cons,'||c.owner||'.'||c.table_name||','||c.constraint_type||','||cc.column_name||','||cc.position||','||c.status||','||c.constraint_name
  FROM dba_constraints c JOIN dba_cons_columns cc ON (cc.owner = c.owner AND cc.constraint_name = c.constraint_name)
 WHERE c.owner NOT LIKE '%SYS%' AND c.owner NOT IN (${EXCLUDE_SCHEMAS}) AND c.constraint_type IN ('P', 'U') ORDER BY 1;
--SELECT 'column,'||owner||'.'||table_name||','||TRIM(TO_CHAR(column_id,'999'))||','||column_name||','||data_type||','||data_length||','||nullable FROM dba_tab_cols
SELECT 'column,'||owner||'.'||table_name||','||column_name||','||data_type||','||data_length||','||nullable FROM dba_tab_cols
 WHERE (owner,table_name) NOT IN (SELECT owner,view_name FROM dba_views)
 AND owner NOT LIKE '%SYS%' AND owner NOT IN (${EXCLUDE_SCHEMAS}) ORDER BY 1;
EXIT
!
) |sort -u > ${COLUMNLIST_NAME}
}

gather_invalid() {
  # Invalid objects
  export INVOBJLIST_NAME=${BASEDIR}/config/`hostname -s`/invalid-${ORACLE_SID}.lst
  tty -s && echo "Invalid Object listing: $INVOBJLIST_NAME"
  (sqlplus -s / as sysdba <<!
set ver off
set feed off
set head off
set lines 100
set pages 0
SELECT owner || '.' || object_name||','||object_type||','||status FROM dba_objects
 WHERE status <> 'VALID' AND object_type NOT IN ('MATERIALIZED VIEW') ORDER BY 1;
exit
!
) > ${INVOBJLIST_NAME}
}

gather_jobs() {
  # Oracle jobs listing
  export JOBLIST_NAME=${BASEDIR}/config/`hostname -s`/jobs-${ORACLE_SID}.lst
  tty -s && echo "Oracle Jobs listing: $JOBLIST_NAME"
  (sqlplus -s / as sysdba <<!
SET pages 2000
SET lines 200
prompt DBMS Scheduler Jobs
SELECT owner, job_name, enabled, state FROM dba_scheduler_jobs ORDER BY 1, 2;
prompt -
prompt DBMS Jobs
SELECT schema_user, job, broken, what FROM dba_jobs ORDER BY 1, 2;
exit
!
) > ${JOBLIST_NAME}
}

gather_storage() {
  # Oracle storage
  export STORAGE_NAME=${BASEDIR}/config/`hostname -s`/storage-${ORACLE_SID}.lst
  tty -s && echo "Oracle storage: $STORAGE_NAME"
  (sqlplus -s / as sysdba <<!
SET pages 0
SET lines 300
SET head off
-- Space usage
SELECT 'Space (GB) occupied by datafiles: '||ROUND(SUM(bytes)/1024/1024/1024,3) gb_used FROM dba_data_files;
SELECT 'Space (GB) occupied by tempfiles: '||ROUND(SUM(bytes)/1024/1024/1024,3) gb_used FROM dba_temp_files;
SELECT 'Space (GB) occupied by segments: '||ROUND(SUM(bytes)/1024/1024/1024,3) gb_used FROM dba_segments;
SELECT 'Space (GB) occupied by online redo logs: '||ROUND(SUM(bytes*members)/1024/1024/1024,3) gb_used FROM v\$log;
SET head on
SET pages 2000
COL tablespace_name FOR A30
COL tablespace FOR A45
COL file FOR A80
COL bytes FOR 99,999,999,999,999
COL maxbytes FOR 99,999,999,999,999
-- Tablespace list
SELECT contents||' Tablespace '||tablespace_name "NAME",block_size,initial_extent,extent_management,allocation_type,segment_space_management,bigfile FROM dba_tablespaces ORDER BY 1;
-- Temporary Tablespace Groups
SELECT 'Tempspace Group: ' || group_name || ' ' || tablespace_name "TEMP TS GROUP" FROM dba_tablespace_groups ORDER BY 1;
-- Temp space usage
PROMPT Temporary Tablespaces in use
SELECT tablespace, SUM(blocks) TOTAL_BLOCKS FROM v\$sort_usage GROUP BY tablespace ORDER BY 2 DESC;
-- Datafiles & tempfiles
SELECT 'Datafile: '||tablespace_name||' '||file_name "FILE", bytes, maxbytes, autoextensible, increment_by FROM dba_data_files ORDER BY 1;
SELECT 'Tempfile: '||tablespace_name||' '||file_name "FILE", bytes, maxbytes, autoextensible, increment_by FROM dba_temp_files ORDER BY 1;
-- Redo logs
SELECT 'Online Redo - thread: '||thread#||'  group: '||group#||' size: '||bytes/1024/1024/1024||' GB  members: '||members "Online Redo" FROM v\$log order by 1;
SELECT 'Standby Redo - thread: '||thread#||'  group: '||group#||' size: '||bytes/1024/1024/1024||' GB' "Standby Redo" FROM v\$standby_log order by 1;
-- Non-system objects in system tablespaces
PROMPT Non-system objects in system tablespaces
SELECT 'Bad TS: '||owner||' '||tablespace_name tablespace, segment_type, COUNT(*) cnt FROM dba_segments
 WHERE tablespace_name LIKE 'SYS%' AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA') 
 GROUP BY owner, tablespace_name, segment_type
 ORDER BY owner, tablespace_name, segment_type;
-- System objects in non-system tablespaces
PROMPT System objects in non-system tablespaces
SELECT 'Bad TS: '||owner||' '||tablespace_name tablespace, segment_type, COUNT(*) cnt FROM dba_segments
 WHERE tablespace_name NOT LIKE 'SYS%' AND tablespace_name IN
       (SELECT tablespace_name FROM dba_tablespaces WHERE contents = 'PERMANENT') AND
       (owner IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA'))
 GROUP BY owner, tablespace_name, segment_type
 ORDER BY owner, tablespace_name, segment_type;
-- Segments allowing parallel operations
PROMPT Segments allowing parallel operations
SELECT 'Parallel Degree: ' || owner || '.' || table_name "TABLE", degree FROM dba_tables WHERE DECODE(degree,'DEFAULT','1',degree) > '1' AND owner NOT LIKE '%SYS%';
SELECT 'Parallel Degree: ' || owner || '.' || table_name "TABLE", index_name, degree FROM dba_indexes WHERE DECODE(degree, 'DEFAULT', 1,degree) > 1 AND owner NOT LIKE '%SYS%'; 
exit
!
) > ${STORAGE_NAME}
}

gather_tables() {
  # General problems and their fixes
  export TABLES_NAME=${BASEDIR}/config/`hostname -s`/tables-${ORACLE_SID}.lst
  tty -s && echo "Table configurations: $TABLES_NAME"
  (sqlplus -s / as sysdba <<!
SET pages 0
SET lines 200
SET feed off
--SELECT owner||','||table_name||','||partitioned||','||temporary FROM dba_tables
SELECT owner||','||table_name||','||temporary FROM dba_tables
WHERE owner NOT LIKE 'APEX%' AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA')        
 ORDER BY 1;
exit
!
) |sort -u > ${TABLES_NAME}
}

gather_indexes() {
  # General problems and their fixes
  export INDEXES_NAME=${BASEDIR}/config/`hostname -s`/indexes-${ORACLE_SID}.lst
  tty -s && echo "Index configurations: $INDEXES_NAME"
  (sqlplus -s / as sysdba <<!
SET pages 0
SET lines 200
SET feed off
--SELECT owner||','||table_name||','||index_name||','||index_type||','||uniqueness||','||compression FROM dba_indexes
SELECT owner||','||table_name||','||index_name||','||index_type||','||uniqueness||','||compression FROM dba_indexes
WHERE owner NOT LIKE 'APEX%' AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA')
ORDER BY 1;
exit
!
) |sort -u > ${INDEXES_NAME}
}

gather_views() {
  # General problems and their fixes
  export VIEWS_NAME=${BASEDIR}/config/`hostname -s`/views-${ORACLE_SID}.lst
  tty -s && echo "View configurations: $VIEWS_NAME"
  (sqlplus -s / as sysdba <<!
SET pages 0
SET lines 200
SET feed off
SELECT owner||','||view_name FROM dba_views
WHERE owner NOT LIKE 'APEX%' AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA')
ORDER BY 1;
exit
!
) |sort -u > ${VIEWS_NAME}
}

gather_sequences() {
  # General problems and their fixes
  export SEQUENCES_NAME=${BASEDIR}/config/`hostname -s`/sequences-${ORACLE_SID}.lst
  tty -s && echo "Sequence configurations: $SEQUENCES_NAME"
  (sqlplus -s / as sysdba <<!
SET pages 0
SET lines 200
SET feed off
--SELECT sequence_owner||','||sequence_name||','||increment_by||','||cycle_flag||','||order_flag||','||cache_size FROM dba_sequences s
SELECT sequence_owner||','||sequence_name||','||increment_by||','||cycle_flag||','||order_flag FROM dba_sequences s
WHERE sequence_owner NOT LIKE 'APEX%' AND sequence_owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA')
ORDER BY 1;
exit
!
) |sort -u > ${SEQUENCES_NAME}
}

gather_triggers() {
  # General problems and their fixes
  export TRIGGERS_NAME=${BASEDIR}/config/`hostname -s`/triggers-${ORACLE_SID}.lst
  tty -s && echo "Trigger configurations: $TRIGGERS_NAME"
  (sqlplus -s / as sysdba <<!
SET pages 0
SET lines 200
SET feed off
SELECT owner||','||trigger_name||','||trigger_type||','||table_name||','||status FROM dba_triggers t
WHERE owner NOT LIKE 'APEX%' AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA')
 ORDER BY 1;
exit
!
) |sort -u > ${TRIGGERS_NAME}
}

gather_security() {
  # General problems and their fixes
  export SECURITY_NAME=${BASEDIR}/config/`hostname -s`/security-${ORACLE_SID}.lst
  tty -s && echo "Security configurations: $SECURITY_NAME"
  (sqlplus -s / as sysdba <<!
SET pages 0
SET lines 200
SET feed off
SELECT 'SYSDBA: ' || username FROM v\$pwfile_users;
SELECT 'DBA: ' || grantee FROM dba_role_privs WHERE granted_role = 'DBA' AND grantee NOT LIKE 'SYS%';
SELECT 'Role,'||ROLE FROM dba_roles;
SELECT 'RoleGrant,'||granted_role||','||grantee FROM dba_role_privs WHERE grantee NOT LIKE '%SYS%' AND grantee NOT LIKE 'APEX%' AND grantee NOT IN (${EXCLUDE_SCHEMAS});
SELECT 'RoleSysPrivs,'||grantee||','||privilege FROM dba_sys_privs WHERE grantee IN (SELECT role FROM dba_roles);
exit
!
) > ${SECURITY_NAME}
}

gather_grants() {
  # Generate all object grants
  export GRANT_NAME=${BASEDIR}/config/`hostname -s`/object_grants-${ORACLE_SID}.lst
  tty -s && echo "Object Grants: $GRANT_NAME"
  (sqlplus -s / as sysdba <<!
set echo off
SET pages 0
SET lines 200
SET feed off
--SELECT 'grant '||listagg(privilege, ',') within GROUP(ORDER BY privilege)||' on '||owner||'.'||table_name||' to '||grantee||decode(grantable,'YES',' with grant option;',';')
SELECT DISTINCT privilege||' on '||owner||'."'||table_name||'" from '||grantee||';'
  FROM dba_tab_privs
 WHERE owner NOT LIKE 'APEX%' AND owner NOT IN (SELECT owner FROM dba_logstdby_skip WHERE statement_opt = 'INTERNAL SCHEMA')
 --GROUP BY owner,table_name,grantee,grantable ORDER BY owner,table_name,grantee;
 ;
exit
!
) |sort -u > ${GRANT_NAME}
}

gather_server() {
  # Per server actions
  export CRONTAB_NAME=${BASEDIR}/crontabs/crontab_`hostname -s`-oracle
  tty -s && echo "writing crontab to: $CRONTAB_NAME"
  crontab -l > ${CRONTAB_NAME} 2>/dev/null

  tty -s && echo "Patch inventories"
  $ORACLE_HOME/OPatch/opatch lsinventory -all -local|grep " /"|grep -v agent|grep -v ":"|sed -e "s/ *//"|while read oh_name oh_dir
  do
    tty -s && echo "Getting patch levels for ${oh_name}"
    export ORACLE_HOME=${oh_dir}
    export PSUINV_NAME=${BASEDIR}/config/`hostname -s`/opatch-${oh_name}.lst
    if [ -x ${ORACLE_HOME}/OPatch/opatch ] ; then
      ${ORACLE_HOME}/OPatch/opatch lsinventory | grep -v "file location" >${PSUINV_NAME}
    fi
    if [ -f $ORACLE_HOME/lib/libodm11.so ] ; then
      ls -l $ORACLE_HOME/lib/libodm11.so|cut -c45- >>${PSUINV_NAME}
    fi
    tty -s && echo "Patch inventory in ${PSUINV_NAME}"
  done

  SRV_CONF_NAME=${BASEDIR}/config/`hostname -s`/server_config.lst
  tty -s && echo "Server configuration in ${SRV_CONF_NAME}"
  cat /etc/redhat-release >${SRV_CONF_NAME}
  uname -a >>${SRV_CONF_NAME}
  # Huge page info
  echo "Huge pages configured: `grep nr_hugepages /etc/sysctl.conf|grep -v "^#"`" >>${SRV_CONF_NAME}
  grep "Huge" /proc/meminfo >>${SRV_CONF_NAME}
  # CRS info
  ls /u001/app/grid/*/bin/crsctl  >/dev/null 2>&1
  RETVAL=$?
  if [ $RETVAL = '0' ] ; then
    for crs in /u001/app/grid/*/bin/crsctl
    do
      echo -e "\nCRS home:${crs%/bin/crsctl}" >>${SRV_CONF_NAME}
      $crs query crs activeversion >>${SRV_CONF_NAME}
      $crs query crs releaseversion >>${SRV_CONF_NAME}
      $crs query crs softwareversion >>${SRV_CONF_NAME}
    done
  fi
}

one_db() {
    tty -s && echo ""
echo "ORACLE_SID ${ORACLE_SID}"
    test_connect ${ORACLE_SID} #|| continue
    export ORACLE_SID

    if [ -n "${PROCNAME}" ] ; then
      ${PROCNAME}
    else
      gather_lic 
      gather_pfile 
      gather_config
      gather_users
      gather_expiring
      gather_segments
      #gather_objects
      gather_grants
      gather_columns
      gather_invalid
      gather_jobs
      gather_storage
      gather_tables
      gather_indexes
      gather_views
      gather_sequences
      gather_triggers
      gather_security
    fi
}

if [ -n "${DB2PROCESS}" ] ; then
  ORACLE_SID=${DB2PROCESS}
  one_db
else
  # Per database actions - run in each running DB (any down instances are skipped)
  for ORACLE_SID in `ps -ef|grep ora_\\\\pmon|cut -d_ -f3-`
  do
    one_db
  done

  gather_server
fi

# Remove any files that failed because the standby didn't allow access
#grep -l ORA-01219 ${BASEDIR}/config/`hostname -s`/*|xargs rm -f
# Remove any empty files
#find ${BASEDIR}/config/`hostname -s` -name "*lst" -size 0 -exec rm {} \;
