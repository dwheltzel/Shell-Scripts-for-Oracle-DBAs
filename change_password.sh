#!/bin/bash
# change_password.sh - changes a user's Oracle password in the prod database
#
# written by Dennis Heltzel

usage() {
  echo "Usage: $0 <Username>"
  exit 1
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

PASSWORD_SIZE=20
. ~/bin/ora_funcs.sh
oe FTSPRD
USER=$1
# 2 options for easily generating a random password
NEWPASS=`openssl rand -base64 ${PASSWORD_SIZE}`
#NEWPASS=`date|md5sum|cut -c-${PASSWORD_SIZE}`

sqlplus -s / as sysdba <<!
alter user $USER identified by "$NEWPASS" account unlock;
prompt Your new password is $NEWPASS
prompt You can change your password anytime with:
prompt alter user $USER identified by "<new password>" replace "$NEWPASS";
prompt Your password will expire in 60 days, please change it before then.

prompt connect $USER/"$NEWPASS"

exit
!
