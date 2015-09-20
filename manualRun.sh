#!/bin/bash

DEV=/dev/sdb1    #need to give yours backup hdd to spind down properly, probably sdb1 will not work on your setup
MNT=/mnt/nas


if [[ $EUID -ne 0 ]]; then
  echo "You must be a root user" 2>&1
  exit 1
else
  mount $DEV $MNT

  DRIVES_MOUNTED=`mount | grep /dev/sdb1 | grep /mnt/nas | wc -l`

  if [ "$DRIVES_MOUNTED" -ge "1" ]; then

    #bash                                   forcing bash enviroment and extra layer PID so renice and others will work nicely from cron and others
    #rsync-backup.vserver:/                 alias for ~/.ssh/config 
    #/mnt/nas/fredy/rsync_backups/vserver   folder where backups are stored
    #vserver                                the name of backuped server
    #verbose                                will display more informations about what is happening at given moment
    bash /opt/rsyncServerBackup/rsync_backup.sh rsync-backup.vserver:/ $MNT/fredy/rsync_backups/vserver vserver verbose

    #flushing, umounting and powering down the backup hdd
    sync
    cd /              #in case you are already inside that drive
    umount $MNT
    hdparm -y $DEV

    echo "Is the harddrive still mounted?:"
    mount | grep /dev/sdb1 | grep /mnt/nas
  fi
fi
