#!/usr/bin/env bash
# Author: Arem Chekunov
# Author email: scorp.dev.null@gmail.com
# repo: https://github.com/sc0rp1us/cehf-useful-scripts
# env and func's
set -x

_BACKUP_NAME="chef-backup_$(date +%Y-%m-%d)"
_BACKUP_USER="root"
_BACKUP_DIR="/var/backups"
_SYS_TMP="/tmp"
_TMP="${_SYS_TMP}/${_BACKUP_NAME}"
_pg_dump(){
su - opscode-pgsql -c "/opt/opscode/embedded/bin/pg_dumpall -c"
}
syntax(){
        echo ""
        echo -e "\t$0 --backup                  # for backup"
        echo -e "\t$0 --restore </from>.tar.bz2 # for restore"
        echo ""
}

_chefBackup(){

echo "Backup function"

id ${_BACKUP_USER} &> /dev/null
    _BACKUP_USER_EXIST=$?
    if [[ ${_BACKUP_USER_EXIST} -ne 0 ]]; then
        echo "You should have a backup user"
    fi


set -e
set -x
# Create folders
mkdir -p ${_TMP}
mkdir -p ${_TMP}/files/etc/opscode
mkdir -p ${_TMP}/files/var/opt/opscode
mkdir -p ${_TMP}/nginx
mkdir -p ${_TMP}/cookbooks
mkdir -p ${_TMP}/postgresql
mkdir -p ${_BACKUP_DIR}/chef-backup

chef-server-ctl org-list  >> ${_TMP}/orglist.txt
chef-server-ctl stop

# Backup files
cp -a /var/opt/opscode ${_TMP}/files/var/opt/opscode
cp -a /etc/opscode ${_TMP}/files/etc/opscode
cp -a /var/opt/opscode/nginx/{ca,etc} ${_TMP}/nginx
cp -a /var/opt/opscode/bookshelf/data/bookshelf/ ${_TMP}/cookbooks

# Backup database
chef-server-ctl start postgresql
_pg_dump > ${_TMP}/postgresql/pg_opscode_chef.sql

cd ${_SYS_TMP}
    if [[ -e ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2 ]]; then
        mv ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2{,.previous}
    fi
    tar cjf ${_BACKUP_DIR}/chef-backup/chef-backup.tar.bz2 ${_BACKUP_NAME}
    chown -R ${_BACKUP_USER}:${_BACKUP_USER} ${_BACKUP_DIR}/chef-backup/
    chmod -R g-rwx,o-rwx ${_BACKUP_DIR}/chef-backup/


    rm -Rf ${_TMP}
chef-server-ctl start
}


_chefRestore(){
echo "Restore function"
    _TMP_RESTORE=${_SYS_TMP}/restore ; mkdir -p ${_TMP_RESTORE}
    if [[ ! -f ${source} ]]; then
        echo "ERROR: file ${source} do not exist"
        exit 1
    fi

    set -e
    set -x
    chef-server-ctl stop
    chef-server-ctl start postgresql
    tar xjf ${source} -C ${_TMP_RESTORE}
        mv /var/opt/opscode/nginx/ca{,.$(date +%Y-%m-%d_%H:%M:%S).bak}
        mv /var/opt/opscode/nginx/etc{,.$(date +%Y-%m-%d_%H:%M:%S).bak}
        if [[ -d /var/opt/opscode/bookshelf/data/bookshelf ]]; then
            mv /var/opt/opscode/bookshelf/data/bookshelf{,.$(date +%Y-%m-%d_%H:%M:%S).bak}
        fi
        _pg_dump > /var/opt/opscode/pg_opscode_chef.sql.$(date +%Y-%m-%d_%H:%M:%S).bak

    cd ${_TMP_RESTORE}/*
    _TMP_RESTORE_D=$(pwd)

        su - opscode-pgsql -c "/opt/opscode/embedded/bin/psql opscode_chef  < ${_TMP_RESTORE_D}/postgresql/pg_opscode_chef.sql"

        cp -a ${_TMP_RESTORE_D}/nginx/ca/              /var/opt/opscode/nginx/
        cp -a ${_TMP_RESTORE_D}/nginx/etc/             /var/opt/opscode/nginx/
        cp -a ${_TMP_RESTORE_D}/cookbooks/bookshelf/   /var/opt/opscode/bookshelf/data/


        chef-server-ctl start
        sleep 30
        chef-server-ctl reconfigure
        sleep 30
        for i in `cat ${_TMP_RESTORE}/orglist.txt`; do
          chef-server-ctl reindex $i
        done

        cd ~
        #rm -Rf ${_TMP_RESTORE}
}

# tests
if [[ ! -x /opt/opscode/embedded/bin/pg_dump ]];then
    echo "Use it script only on chef-server V11"
    exit 1
fi

if [[ $(id -u) -ne 0 ]]; then
    echo "You should to be root"
    exit 1
fi

# body
while [ "$#" -gt 0 ] ; do
    case "$1" in
        -h|--help)
            syntax
            exit 0
            ;;
        --backup)
            action="backup"
            shift 1
            ;;
        --restore)
            action="restore"
            source="${2}"
            break
            ;;
        *)
            syntax
            exit 1
            ;;

    esac
done


if [[ ${action} == "backup" ]];then
        _chefBackup
elif [[ ${action} == "restore" ]];then
        _chefRestore
else
        syntax
        exit 1
fi
