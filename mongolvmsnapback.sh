#!/bin/bash
#
# MongoDB LVM snapshot backup script
#
# Jean-Francois Theroux <failshell@gmail.com>
#
# This script allows to backup either a MongoDB replica set node with minimal downtime.
# At the same time, it's possible to use this script to backup a sharded cluster. The only
# thing that needs to be done to do so is to stop the balancer.
#
# That can be done in 2 ways:
# - a CRON that runs on one config node
# - Setup a backup window : http://docs.mongodb.org/manual/tutorial/schedule-backup-window-for-sharded-clusters/

# settings
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
ARCHIVE_DIR=
MNT_DIR=
VG=
LV=
MODE=
CFG_NODE=

# archiving settings
DOW=`date +%w`
DOM=`date +%d`
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=1

# functions
get_status () {
  if [ $? == 0 ]
  then
    echo OK
  else
    echo ERROR
    echo
    echo [!] Something fatal happened. Aborting.

    # unlocking node
    echo
    echo -n "[-] Unlocking MongoDB node: "
    mongo --eval "db.fsyncUnlock()" > /dev/null 2>&1
    if [ $? == 0 ]
    then
      echo OK
    else
      echo ERROR
    fi

    # Unmount if we're mounted
    echo
    echo -n "[-] Is ${MNT_DIR} mounted: "
    mount | grep ${MNT_DIR} > /dev/null 2>&1
    if [ $? == 0 ]
    then
      echo Yes
      echo -n "[-] Unmounting ${MNT_DIR}: "
      cd / && umount ${MNT_DIR}
      if [ $? == 0 ]
      then
        echo OK
      else
        echo ERROR
      fi
    else
      echo No
    fi

    # If we have a leftover snapshot, remove it
    echo
    echo -n "[-] Do we have a leftover snapshot: "
    if [ -L ${VOLUME}-snapshot ]
    then
      echo Yes
      echo -n "[-] Removing snapshot: "
      lvremove -f ${VOLUME}-snapshot > /dev/null 2>&1
      if [ $? == 0 ]
      then
        echo OK
      else
        echo ERROR
      fi
    else
      echo No
    fi

    echo
    echo [-] `date`
    echo [+] MongoDB LVM snapshot backup status: failure
    exit 1
  fi

}

echo [+] Starting MongoDB LVM snapshot backup
echo [-] `date`
echo

# pre flight tests
[ -x /usr/bin/mongo ] || { echo "ERROR: Missing mongo client. Aborting."; exit 1; }
[ -x /sbin/lvcreate ] || { echo "ERROR: Missing LVM tools. Aborting."; exit 1; }
[ -d ${MNT_DIR} ] || { echo "[!] Missing ${MNT_DIR}. Creating it." && mkdir -p ${MNT_DIR}; }
[ -d ${ARCHIVE_DIR} ] || { echo "[!] Missing ${ARCHIVE_DIR}. Creating it." && mkdir -p ${ARCHIVE_DIR}; }
[ -d ${ARCHIVE_DIR}/daily ] || { echo "[!] Missing ${ARCHIVE_DIR}/daily. Creating it." && mkdir -p ${ARCHIVE_DIR}/daily; }
[ -d ${ARCHIVE_DIR}/weekly ] || { echo "[!] Missing ${ARCHIVE_DIR}/weekly. Creating it." && mkdir -p ${ARCHIVE_DIR}/weekly; }
[ -d ${ARCHIVE_DIR}/monthly ] || { echo "[!] Missing ${ARCHIVE_DIR}/monthly. Creating it." && mkdir -p ${ARCHIVE_DIR}/monthly && echo; }

if [ -z "$VG" ]
then
  echo "[!] Volume group is not set. Aborting."
  exit 1
fi
if [ -z "$LV" ]
then
  echo "[!] Logical volume is not set. Aborting."
  exit 1
fi

# Make sure the balancer is stopped
if [ "${MODE}" == "sharded" ]
then
  mongo ${CFG_NODE}:27019 --eval 'sh.getBalancerState()' | grep true > /dev/null 2>&1
  if [ $? = 0 ]
  then
    echo "[!] Balancer is running. Aborting."
    exit 1
  fi
fi

echo [+] Pre flight tests complete
echo

# Backup
echo [+] Backup phase
# locking node
echo -n "[-] Locking MongoDB node: "
mongo --eval "db.fsyncLock()" > /dev/null 2>&1
get_status

# LVM snapshot
VOLUME=/dev/${VG}/${LV}
echo -n "[-] Creating LVM snapshot of ${VOLUME} as ${VOLUME}-snapshot: "
lvcreate -s "/dev/${VG}/${LV}" -n "${LV}-snapshot" -l "90%FREE" > /dev/null 2>&1
get_status

# mounting snapshot
echo -n "[-] Mounting snapshot under ${MNT_DIR}: "
mount ${VOLUME}-snapshot ${MNT_DIR} > /dev/null 2>&1
get_status

# compressing data
echo -n "[-] Compressing snapshot and copying it to ${ARCHIVE_DIR}: "
cd ${MNT_DIR} && tar czf ${ARCHIVE_DIR}/daily/mongo-${HOSTNAME}-`date +%F`.tar.gz . && cd /
get_status

#unlocking node
echo -n "[-] Unlocking MongoDB node: "
mongo --eval "db.fsyncUnlock()" > /dev/null 2>&1
get_status

# symlink to latest
[ -L ${ARCHIVE_DIR}/latest ] && { rm -f ${ARCHIVE_DIR}/latest; echo [-] Removed old latest symlink; }
echo -n "[-] Symlinking last backup to ${ARCHIVE_DIR}/latest: "
ln -sf ${ARCHIVE_DIR}/daily/mongo-${HOSTNAME}-`date +%F`.tar.gz ${ARCHIVE_DIR}/latest > /dev/null 2>&1
get_status

# unmounting snapshot
echo -n "[-] Unmounting snapshot: "
umount ${MNT_DIR} > /dev/null 2>&1
get_status

# remove snapshot
echo -n "[-] Removing snapshot: "
lvremove -f ${VOLUME}-snapshot > /dev/null 2>&1
get_status

# remove temp dir
echo -n "[-] Removing ${TMP_DIR}: "
rm -rf ${TMP_DIR}
get_status

# Archiving
echo
echo [+] Archiving phase
# daily
echo -n "[-] Keeping ${KEEP_DAILY} daily backups: "
cd ${ARCHIVE_DIR}/daily && (ls -t|head -n ${KEEP_DAILY};ls)|sort|uniq -u|xargs rm -f
get_status

# weekly
if [ ${DOW} == 0 ]
then
  echo -n "[-] We're the first day of the week, archiving: "
  cp ${ARCHIVE_DIR}/daily/mongo-${HOSTNAME}-`date +%F`.tar.gz ${ARCHIVE_DIR}/weekly/
  get_status
  echo -n "[-] Keeping ${KEEP_WEEKLY} weekly backups: "
  cd ${ARCHIVE_DIR}/weekly && (ls -t|head -n ${KEEP_WEEKLY};ls)|sort|uniq -u|xargs rm -f
  get_status
else
  echo [-] Not the first day of the week. Skipping weekly archiving.
fi

# monthly
if [ ${DOM} == 01 ]
then
  echo -n "[-] We're the first day of the month, archiving: "
  cp ${ARCHIVE_DIR}/daily/mongo-${HOSTNAME}-`date +%F`.tar.gz ${ARCHIVE_DIR}/monthly/
  get_status
  echo -n "[-] Keeping ${KEEP_MONTHLY} monthly backups: "
  cd ${ARCHIVE_DIR}/monthly && (ls -t|head -n ${KEEP_MONTHLY};ls)|sort|uniq -u|xargs rm -f
  get_status
else
  echo [-] Not the first day of the month. Skipping monthly archiving.
fi

echo
echo [-] `date`
echo [+] MongoDB LVM snapshot backup status: success
