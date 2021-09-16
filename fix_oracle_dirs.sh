# fix_oracle_dirs.sh
#
# Written by Dennis Heltzel, August 2021
# This will scan the Oracle directories in the current database and write DDL to:
# 1) fix any paths with symlinks (will not work in 19c)
# 2) drop dirs with invalid paths (unreachable)
#
DIRLIST=${ORACLE_SID}-directories.lst
FIXSQL=${ORACLE_SID}-fix_dirs.sql
:> ${DIRLIST}
:> ${FIXSQL}
tty -s && echo "processing database ${ORACLE_SID}"
tty -s && echo "list of all directories: ${DIRLIST}"
tty -s && echo "DDL to fix directories: ${FIXSQL}"

# Get directory info from database
(sqlplus -s / as sysdba <<!
set pages 0
set lines 200
set head off
set feed off
select DIRECTORY_PATH||':'||owner||':'||DIRECTORY_NAME from dba_directories;
exit
!
) > ${DIRLIST}

# Loop through each found directory and write DDL if needed
cat ${DIRLIST} | while IFS=: read -r old_path owner dirname;do
  if `ls -d $old_path >/dev/null 2>&1` ; then
    new_path=`readlink -m $old_path`
    if [ $new_path != $old_path ] ; then
      echo "as $owner, CREATE OR REPLACE DIRECTORY $dirname AS '$new_path';" >>${FIXSQL}
    fi
  else
    echo "as $owner, DROP DIRECTORY $dirname;" >>${FIXSQL}
  fi
done
# Display the results
cat ${FIXSQL}

