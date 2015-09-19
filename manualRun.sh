#!/bin/bash

#bash                                   forcing bash enviroment and extra layer PID so renice and others will work nicely from cron and others
#rsync-backup.vserver:/                 alias for ~/.ssh/config 
#/mnt/nas/fredy/rsync_backups/vserver   folder where backups are stored
#vserver                                name of backuped server
#verbose                                will display more informations about what is happening at given moment
bash ./rsync_backup.sh rsync-backup.vserver:/ /mnt/nas/fredy/rsync_backups/vserver vserver verbose


#powering down the backup hdd
sync
hdparm -y /dev/sdb1    #need to give yours backup hdd, probably sdb1 will not work on your setup
