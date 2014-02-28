#!/bin/bash
#
# LVM snapshot rotate script
# Jay R. Wren <jwren@arbor.net>
#
# forked from mongolvmsnapback by
#
# Jean-Francois Theroux <failshell@gmail.com>
#
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
: ${ARCHIVE_DIR:=/archives}
: ${VG:=$(vgs --noheadings | awk '{print $1}')}
: ${LVS:=$(lvs --noheadings | awk '$3!~/^s/{print $1}')}

# archiving settings
DOW=`date +%w`
DOM=`date +%d`
# TODO: support multiple daily, weekly, monthly
#KEEP_DAILY=7
#KEEP_WEEKLY=4
#KEEP_MONTHLY=1

# functions
get_status () {
  if [ $? == 0 ]
  then
    echo OK
  else
    [[ $1 == first ]] && { echo assuming first run ; return 0; }
    echo ERROR
    echo
    echo [!] Something fatal happened. Aborting.

    # Unmount if we're mounted
    echo
    echo -n "[-] Is ${ARCHIVE_DIR}/daily mounted: "
    mount | grep ${ARCHIVE_DIR} > /dev/null 2>&1
    if [ $? == 0 ]
    then
      echo Yes
      echo -n "[-] Unmounting ${ARCHIVE_DIR}: "
      cd / && umount ${ARCHIVE_DIR}
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
    echo [+] LVM snapshot rotate status: failure
    exit 1
  fi

}

echo [+] Starting LVM snapshot rotate
echo [-] `date`
echo

if [ -z "$VG" ]
then
  echo "[!] Volume group is not set. Aborting."
  exit 1
fi

[ -x /sbin/lvcreate ] || { echo "ERROR: Missing LVM tools. Aborting."; exit 1; }

for LV in $LVS; do
[ -d ${ARCHIVE_DIR}/daily/$LV ] || { echo "[!] Missing ${ARCHIVE_DIR}/daily/$LV. Creating it." && mkdir -p ${ARCHIVE_DIR}/daily/$LV; }
[ -d ${ARCHIVE_DIR}/weekly/$LV ] || { echo "[!] Missing ${ARCHIVE_DIR}/weekly/$LV. Creating it." && mkdir -p ${ARCHIVE_DIR}/weekly/$LV; }
[ -d ${ARCHIVE_DIR}/monthly/$LV ] || { echo "[!] Missing ${ARCHIVE_DIR}/monthly/$LV. Creating it." && mkdir -p ${ARCHIVE_DIR}/monthly/$LV && echo; }

if [ -z "$LV" ]
then
  echo "[!] Logical volume is not set. Aborting."
  exit 1
fi


echo [+] Pre flight tests complete
echo

VOLUME=/dev/${VG}/${LV}

# unmounting snapshot
echo -n "[-] Unmounting snapshot: "
umount ${ARCHIVE_DIR}/daily/$LV
get_status first

# remove snapshot
echo -n "[-] Removing snapshot: "
lvremove -f ${VOLUME}-snapshot >/dev/null
get_status first

# LVM snapshot
echo -n "[-] Creating LVM snapshot of ${VOLUME} as ${VOLUME}-snapshot: "
lvcreate -s "/dev/${VG}/${LV}" -n "${LV}-snapshot" -l "2%ORIGIN" -p r >/dev/null 2>&1
get_status

# mounting snapshot
echo -n "[-] Mounting snapshot under ${ARCHIVE_DIR}: "
mount ${VOLUME}-snapshot ${ARCHIVE_DIR}/daily/$LV
get_status

# Archiving
echo
echo [+] Archiving phase

# weekly
if [ ${DOW} == 0 ]
then
  echo -n "[-] We're the first day of the week, archiving: "
  umount $ARCHIVE_DIR/weekly/$LV
  lvremove -f ${VOLUME}-snapshot-weekly >/dev/null
  lvcreate -s "/dev/${VG}/${LV}" -n "${LV}-snapshot-weekly" -l "2%ORIGIN" -p r >/dev/null 2>&1
  mount $VOLUME-snapshot-weekly $ARCHIVE_DIR/weekly/$LV
  get_status
else
  echo [-] Not the first day of the week. Skipping weekly archiving.
  if [[ ! -b /dev/${VG}/${LV}-snapshot-weekly ]];then
    echo -n "[-] We're the first run, weekly archiving: "
    lvremove -f ${VOLUME}-snapshot-weekly >/dev/null
    lvcreate -s "/dev/${VG}/${LV}" -n "${LV}-snapshot-weekly" -l "2%ORIGIN" -p r >/dev/null 2>&1
    mount $VOLUME-snapshot-weekly $ARCHIVE_DIR/weekly/$LV
    get_status
  fi
fi

# monthly
if [ ${DOM} == 01 ]
then
  echo -n "[-] We're the first day of the month, archiving: "
  umount $ARCHIVE_DIR/monthly/$LV
  lvremove -f ${VOLUME}-snapshot-monthly >/dev/null
  lvcreate -s "/dev/${VG}/${LV}" -n "${LV}-snapshot-monthly" -l "2%ORIGIN" -p r >/dev/null 2>&1
  mount $VOLUME-snapshot-monthly $ARCHIVE_DIR/monthly/$LV
  get_status
else
  echo [-] Not the first day of the month. Skipping monthly archiving.
  if [[ ! -b /dev/${VG}/${LV}-snapshot-monthly ]];then
    echo -n "[-] We're the first run, monthly archiving: "
    lvremove -f ${VOLUME}-snapshot-monthly >/dev/null
    lvcreate -s "/dev/${VG}/${LV}" -n "${LV}-snapshot-monthly" -l "2%ORIGIN" -p r >/dev/null 2>&1
    mount $VOLUME-snapshot-monthly $ARCHIVE_DIR/monthly/$LV
    get_status
  fi
fi

done

echo
echo [-] `date`
echo [+] LVM snapshot rotate status: success

