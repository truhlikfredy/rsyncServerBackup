#!/bin/bash

ADMIN_EMAIL=anton.krug@gmail.com  #Change the email to yours!

#ucomment if you DON'T want to perform any operations with backups
#DEBUG="DEBUG"

#weaker arcfour encryption (useful on trusted LAN connection to low performance server )
#compression is not handled on SSH level
SSH="ssh -c arcfour -o Compression=no"

COMPRESS_WITH_RSYNC="-z"        #uncoment if you want compress rsync transmition on RSYNC level

# The number of days to keep in each type of backup.
# Set the value of WEEKLYHISTORY or MONTHLYHISTORY to 0 to skip a particular type
DAILYHISTORY=6       # 6 +1 = 7 days old backups ( including curent ) 
#WEEKLYHISTORY=27     # less weekly backups 
WEEKLYHISTORY=34     # 3 weekly backups ((3 weeks+1)*7)-1=27 days    ((4 weeks+1)*7)-1=34days
MONTHLYHISTORY=370   # 12 monthly backups

SHELL_REQUIRED=bash

#paths to tools, this can be different for each platform, at moment it runs x86 debian,
#in past it was running Raspberry PI and before NSLUG2.

RSYNC=/usr/bin/rsync           #RSYNC=/opt/bin/rsync
TR=/usr/bin/tr                 #TR=/opt/bin/coreutils-tr
FIND=/usr/bin/find             #FIND=/opt/bin/findutils-find        
CP=/bin/cp                     #CP=/opt/bin/coreutils-cp
MV=/bin/mv                     #MV=/opt/bin/coreutils-mv
SEQ=/usr/bin/seq               #SEQ=/opt/bin/coreutils-seq
READLINK=/bin/readlink         #READLINK=/opt/bin/coreutils-readlink
BASENAME=/usr/bin/basename     #BASENAME=/opt/bin/coreutils-basename
DATE=/bin/date                 #DATE=/opt/bin/coreutils-date
TEE=/usr/bin/tee               #TEE=/opt/bin/tee
RM=/bin/rm                     #RM=/opt/bin/coreutils-rm
TOUCH=/usr/bin/touch           #TOUCH=/opt/bin/coreutils-touch
LN=/bin/ln                     #LN=/opt/bin/coreutils-ln
CHMOD=/bin/chmod               #CHMOD=/opt/bin/coreutils-chmod
RENICE=/usr/bin/renice         #RENICE=/opt/bin/renice    
PS=/bin/ps                     #PS=/opt/bin/procps-ps
CUT=/usr/bin/cut               #CUT=/opt/bin/coreutils-cut
TAIL=/usr/bin/tail             #TAIL=/opt/bin/coreutils-tail
SLEEP=/bin/sleep               #SLEEP=/opt/bin/coreutils-sleep
NAIL=/usr/bin/bsd-mailx        #NAIL=/opt/bin/nail 
ECHO=/bin/echo                 #ECHO=/opt/bin/coreutils-echo
CAT=/bin/cat                   #CAT=/opt/bin/coreutils-cat
TIME=/usr/bin/time             #TIME=/opt/usr/bin/time
DELAY_TIME=5                   #DELAY_TIME=5

SRC=$1
ROOTPATH=$2
HFRENDLYNAME=$3
VERBOSE=$4


START=$($DATE +%s)

LOG_FILE=$ROOTPATH/backup_current.log
RSYNC_ERROR=$ROOTPATH/_rsync_exit_status
MONTH_FILE=$ROOTPATH/backup_month.log
FULL_FILE=$ROOTPATH/backup_full.log
#EMAIL_LOG_FILE=/tmp/`expr match "$0" '.*\/\(.*\)\..*'`.log
EMAIL_LOG_FILE=$ROOTPATH/backup_email.log

#storing name of curent (today will be made new one) backup
OLD_DIR=`$BASENAME \`$READLINK $ROOTPATH/@current\``

dateDiff() {
  sec=86400
  dte1=`$DATE --utc -d "$1" +%s`
  dte2=`$DATE --utc -d "$2" +%s`
  diffSec=$((dte2-dte1))
  if ((diffSec < 0)); then abs=-1; else abs=1; fi
    $ECHO $((diffSec/sec*abs))
  }

  get_whole_date() {
    $ECHO `$BASENAME "$1"` | cut -d _ -f 2
  }

  get_date() {
    datum=`get_whole_date "$2"`
    if [ "$1" = "y" ]; then
      $ECHO $datum | cut -d - -f 1
    fi
    if [ "$1" = "m" ]; then
      $ECHO $datum | cut -d - -f 2
    fi
    if [ "$1" = "d" ]; then
      $ECHO $datum | cut -d - -f 3
    fi
    if [ "$1" = "w" ]; then
      $DATE -d "$datum" +%3V
    fi
  }

  get_name() {
    if [ "$1" = "d" ]; then
      $ECHO d_`$DATE -d "$2" +%Y-%m-%d`_`$DATE -d "$2" +%a | $TR '[:upper:]' '[:lower:]'`
    fi
    if [ "$1" = "w" ]; then
     $ECHO w_`$DATE -d "$2" +%Y-%m-%d`_`$DATE -d "$2" +%3V`
   fi
   if [ "$1" = "m" ]; then
     $ECHO m_`$DATE -d "$2" +%Y-%m-%d`_`$DATE -d "$2" +%b | $TR '[:upper:]' '[:lower:]'`
   fi
 }

 clean_uncomplete() {
  for backup in `$FIND $ROOTPATH/d_* -maxdepth 0 2>/dev/null`
  do
   backup_name=`$BASENAME $backup`
   if [ ! -f "$ROOTPATH/$backup_name/@BackupTime" ]; then
     $ECHO "Deleting $backup_name because it's not complete backup (@BackupTime file is missing)"
     if [ -z $DEBUG ]; then
      $RM -rf $ROOTPATH/$backup_name
      $SLEEP $DELAY_TIME
    fi
  fi
done
}

month_rotate() {
  year=`get_date "y" "$1"`
  month=`get_date "m" "$1"`    
  last_day_date=`$DATE -d "$year-$month-01 +1 month -1 day" +%Y-%m-%d`    #find out last day of given month
  month_name=`get_name "m" "$last_day_date"`                                    #generate MONTH name for that day
  if [ ! -d "$ROOTPATH/$month_name" ]; then
    last_day=`$DATE -d "$last_day_date" +%d`          #get number of the last day like 31th
    for a in `$SEQ $last_day`                           #loop var "a" from 0 to 31
    do
      from_backup=`get_name "d" "$last_day_date +1 day -$a day"`    #subtract "a" from the last day
      if [ -d "$ROOTPATH/$from_backup" ]; then
        $ECHO "MONTH backup copying $from_backup to $month_name"
        if [ -z $DEBUG ]; then
          $RM -rf $ROOTPATH/$month_name
          $SLEEP $DELAY_TIME
          $CP -al $ROOTPATH/$from_backup $ROOTPATH/$month_name
          $SLEEP $DELAY_TIME
        fi
        $ECHO
        return 0
      fi
    done
  fi
}

week_move() {
  if [ "$WEEKLYHISTORY" = 0 ]; then
    $ECHO "skipping WEEK backups so I delete safely $1"
    if [ -z $DEBUG ]; then
      $RM -rf $ROOTPATH/$1
      $SLEEP $DELAY_TIME
    fi
  else
  if [ ! -d "$ROOTPATH/$2" ]; then
    $ECHO "WEEK backup moving/coping $1 to $2"
    if [ -z $DEBUG ]; then
      $RM -rf $ROOTPATH/$2
      $SLEEP $DELAY_TIME
      if [ "$OLD_DIR" = "$1" ]; then         
        $CP -al $ROOTPATH/$1 $ROOTPATH/$2
        $ECHO "It's copied because $1 is last backup (it's our freshest backup what we have avaible)!"
      else
        $MV $ROOTPATH/$1 $ROOTPATH/$2
        $ECHO "It's moved"
      fi
      $SLEEP $DELAY_TIME
    fi
    else
      $ECHO "WEKK backup already exists, I will delete $1"
      $RM -rf $ROOTPATH/$1
      $SLEEP $DELAY_TIME
    fi
  fi
}

clean_day_n_check_week_backup() {
  day_in_week=`$DATE -d "$1" +%u`
  last_day_in_week=`$DATE -d "$1 +7 day -$day_in_week day" +%Y-%m-%d`

  week_name=`get_name "w" "$last_day_in_week"`
  den_v_tyzdny=`$DATE -d "$1" +%u`          #get what day number in week is that day
  #    $ECHO "checking for existing backup after $1 till $last_day_in_week (it's after $den_v_tyzdny day in the week $week_name)"

  if [ "$den_v_tyzdny" = "7" ]; then
    week_move $(get_name d $last_day_in_week) $week_name
    return 0
  fi

  for a in `$SEQ $den_v_tyzdny 6`
  do
    from_backup=`get_name "d" "$last_day_in_week -6 day +$a day"`
    #            $ECHO $from_backup
    if [ -d "$ROOTPATH/$from_backup" ]; then
      $ECHO "deleting $1 because it's old and $from_backup exists => so $1 it's not last backup in the week $week_name"
      if [ -z $DEBUG ]; then
        $RM -rf $ROOTPATH/$(get_name d $1)
      fi
      $ECHO
      return 0
    fi
  done

  from_backup=`get_name "d" "$1"`
  $ECHO "the $from_backup is not sunday backup but it's last DAY backup for the week $week_name so I will make WEEK backup from it"
  week_move $from_backup $week_name
}

rotate_all() {
  #cleaning old MONTH and WEEK backups

  $ECHO "Cleaning MONTH backups"    
  $FIND $ROOTPATH/m_* -maxdepth 0 -daystart -mtime +$MONTHLYHISTORY 2>/dev/null
  if [ -z $DEBUG ]; then
    $FIND $ROOTPATH/m_* -maxdepth 0 -daystart -mtime +$MONTHLYHISTORY -exec $RM -rf {} \; 2>/dev/null
    $SLEEP $DELAY_TIME
  fi
  $ECHO

  $ECHO "Cleaning WEEK backups"    
  $FIND $ROOTPATH/w_* -maxdepth 0 -daystart -mtime +$WEEKLYHISTORY 2>/dev/null
  if [ -z $DEBUG ]; then
    $FIND $ROOTPATH/w_* -maxdepth 0 -daystart -mtime +$WEEKLYHISTORY -exec $RM -rf {} \; 2>/dev/null
    $SLEEP $DELAY_TIME
  fi
  $ECHO

  $ECHO "Rotating old backups for $ROOTPATH"
  $ECHO     

  # making MONTH backups
  if [ "$MONTHLYHISTORY" = 0 ]; then
    $ECHO "skipping monthly rotation"
    $ECHO
  else
    now_month=`$DATE +%m`
    for a in `$FIND $ROOTPATH/d_* -maxdepth 0 | sort`
    do
      month=`get_date "m" "$a"`
      if [ ! "$now_month" = "$month" ]; then
        month_rotate `get_whole_date $a`
      fi
    done
  fi


  # cleaning DAY backups and making weekly backups
  for a in `$FIND $ROOTPATH/d_* -maxdepth 0 | sort`
  do
    tmp_date=`get_whole_date "$a"`
    #   $ECHO " now - $tmp_date => ( `$DATE --utc -d "$tmp_date" +%s` - `$DATE --utc -d "now" +%s` ) / 86400 > $DAILYHISTORY"
    #   $ECHO "$(dateDiff 'now' $tmp_date)";

    if [ "$(dateDiff 'now' $tmp_date)" -gt "$DAILYHISTORY" ]; then
      #     $ECHO "den $tmp_date je stary, idem zistit ci zmazat alebo presunut"
      clean_day_n_check_week_backup $tmp_date
      #     $ECHO 
    else
      $ECHO "Resting days like $tmp_date are to young to be deleted and so I quit with this checks."
      $ECHO 
      return 0
    fi
  done
}

prepare_list() {
  $ECHO "Creating list for backup..."
  if [ "$($DATE +%u)" = "7" ]; then
    $ECHO "It's last day in week (sunday)"
    WEEK=1
  else
    WEEK=0
  fi
  if [ "$($DATE -d "+1 day" +%d)" = "01" ]; then
    $ECHO "It's last day in month"
    MONTH=1
  else
    MONTH=0
  fi
  $ROOTPATH/backup.sh "$ROOTPATH" backup.lst $WEEK $MONTH
  $ECHO
}

main_backup() {
  mkdir $ROOTPATH/e============ 1>/dev/null 2>&1
  mkdir $ROOTPATH/n============ 1>/dev/null 2>&1
  mkdir $ROOTPATH/z============ 1>/dev/null 2>&1
  mkdir $ROOTPATH/z_packed 1>/dev/null 2>&1


  $ECHO "Checking for uncomplete backups in $ROOTPATH"
  clean_uncomplete
  $ECHO

  $ECHO "Rotating all necesary backups in $ROOTPATH"
  rotate_all
  $ECHO

  $ECHO "Backing up \"$SRC\" to $ROOTPATH/$TODAY_DIR"
  if [ "$VERBOSE" = "verbose" ]; then
    MAYBE_VERBOSE="-v"
  else
    MAYBE_VERBOSE=""
  fi
  RSTART=$($DATE +%s)

  prepare_list
  if [ "$VERBOSE" = "verbose" ]; then
    $ECHO "Calling this command:"
    $ECHO "rsync -a $COMPRESS_WITH_RSYNC -H $MAYBE_VERBOSE -h -h --numeric-ids --inplace --stats --delete --delete-excluded --exclude-from=$ROOTPATH/backup.lst -e "$SSH" --rsync-path="sudo rsync" --link-dest=$ROOTPATH/$OLD_DIR $SRC $ROOTPATH/$TODAY_DIR"
    $ECHO 
  fi
  if [ -z $DEBUG ]; then

    $RSYNC -a $COMPRESS_WITH_RSYNC -H $MAYBE_VERBOSE -h -h --numeric-ids --inplace --stats --delete --delete-excluded --exclude-from=$ROOTPATH/backup.lst -e "$SSH" --rsync-path="sudo rsync" --link-dest=$ROOTPATH/$OLD_DIR $SRC $ROOTPATH/$TODAY_DIR 2>&1

    RSYNC_EXIT=$?

    if [ "$RSYNC_EXIT" = "0" ]; then
      $ECHO "rsync finished successfully"
    else
      #0 Success
      #1 Syntax or usage error
      #2 Protocol incompatibility
      #3 Errors selecting input/output files, dirs
      #4 Requested action not supported: an attempt was made to manipulate 64-bit files on a platform that cannot support them; or an option was specified that is supported by the client and not by the server.
      #5 Error starting client-server protocol
      #6 Daemon unable to append to log-file
      #10 Error in socket I/O
      #11 Error in file I/O
      #12 Error in rsync protocol data stream
      #13 Errors with program diagnostics
      #14 Error in IPC code
      #20 Received SIGUSR1 or SIGINT
      #21 Some error returned by waitpid()
      #22 Error allocating core memory buffers
      #23 Partial transfer due to error
      #24 Partial transfer due to vanished source files
      #25 The --max-delete limit stopped deletions
      #30 Timeout in data send/receive
      #35 Timeout waiting for daemon connection
      
      #$TOUCH $ROOTPATH/$RSYNC_EXIT           #once on NSLUG was this needed because tee and echo got broken, before coreutils versions were used
      $ECHO "$RSYNC_EXIT" >> $RSYNC_ERROR
      $ECHO "!!!!!!!!!!!!!!!!!!!!!!!!"
      $ECHO "!!!!!! rsync error $?!!!!"
      $ECHO "!!!!!!!!!!!!!!!!!!!!!!!!"
    fi

    if [ -d "$ROOTPATH/$TODAY_DIR" ]; then
      $RM -f $ROOTPATH/$TODAY_DIR/@BackupTime
      $DATE > $ROOTPATH/$TODAY_DIR/@BackupTime
    fi

    if [ "$RSYNC_EXIT" = "0" ]; then
      $RM $ROOTPATH/@current
      $LN -s $ROOTPATH/$TODAY_DIR $ROOTPATH/@current
    fi
  fi

  $ECHO ""

  #measure how long rsync took to finish
  REND=$($DATE +%s)
  RDIFF=$(( $REND - $RSTART ))
  let RMINS=$RDIFF/60
  let RHOURS=$RMINS/60
  $ECHO "Total time of \"rsync\" = $RHOURS hours ( $RMINS mins => $RDIFF seconds)"

  #try to compress only if rsync exited correctly
  if [ "$RSYNC_EXIT" = "0" ]; then
    if [ -f "$ROOTPATH/@compress_next_backup" ] && [ -f "$ROOTPATH/compress.sh" ]; then
      $ECHO "Found the compress tag, will execute compression"

      #call given to compression script
      $ROOTPATH/compress.sh $ROOTPATH $TODAY_DIR

      #remove the tag
      $RM $ROOTPATH/@compress_next_backup

      #measure time how long it took
      CEND=$($DATE +%s)
      CDIFF=$(( $CEND - $REND ))
      let CMINS=$CDIFF/60
      let CHOURS=$CMINS/60
      $ECHO "Total time of \"compression\" = $CHOURS hours ( $CMINS mins => $CDIFF seconds)"
    fi
  fi

}

sanity_checks() {
  if [ ! -f "$ECHO" ]; then
    echo "Path to echo command ($ECHO) doesn't exist."
    return 1
  fi

  if [ ! -f "$CAT" ] || [ ! -f "$NAIL" ] || [ ! -f "$SLEEP" ] || [ ! -f "$CUT" ] || [ ! -f "$TAIL" ]; then
    $ECHO "Paths to tools (cat nail sleep cut tail) aren't setup properly." 
    return 1
  fi   
  if [ ! -f "$PS" ] || [ ! -f "$RENICE" ] || [ ! -f "$CHMOD" ] || [ ! -f "$RM" ] || [ ! -f "$TOUCH" ]; then
    $ECHO "Paths to tools (ps renice chmod rm touch)  aren't setup properly." 
    return 1
  fi   
  if [ ! -f "$LN" ] || [ ! -f "$TEE" ] || [ ! -f "$DATE" ] || [ ! -f "$BASENAME" ] || [ ! -f "$READLINK" ]; then
    $ECHO "Paths to tools (ln tee date basename readlink) aren't setup properly." 
    return 1
  fi   
  if [ ! -f "$SEQ" ] || [ ! -f "$MV" ] || [ ! -f "$TR" ] || [ ! -f "$CP" ] ||  [ ! -f "$FIND" ] ||  [ ! -f "$TIME" ]; then
    $ECHO "Paths to tools (seq mv tr cp find time) aren't setup properly." 
    return 1
  fi   

  MYSHELL=`$PS -p $$ | $TAIL -n 1 | $CUT -d ":" -f 3 | $CUT -d " " -f 2`

  if [ ! "$SHELL_REQUIRED" = "$MYSHELL" ]; then
    $ECHO "Required shell '$SHELL_REQUIRED' is not '$MYSHELL' !"
    return 1
  fi

  if [ -z "$SRC" ] || [ -z "$HFRENDLYNAME" ] || [ -z "$VERBOSE" ] || [ -z "$ROOTPATH" ]; then                        
    $ECHO "Usage: rsync_backup.sh SRC PATH HUMAN_FRENDLY_NAME VERBOSITY" 
    $ECHO "  eg.: rsync_backup.sh root@server.com:/dir/to/backup /path/where/store/backup just_human_frendly_name_of_server verbose" 
    return 1
  fi

  if [ ! -d "$ROOTPATH" ]; then                        
    $ECHO "ROOTPATH directory ('$ROOTPATH') does not exist" 
    return 1
  fi

  if [ ! -d "$ROOTPATH/$OLD_DIR" ]; then
    $ECHO
    $ECHO "****************************************************************"
    $ECHO "$tmp_var doesn't exists or reading @current symlink failed !!!"
    $ECHO "****************************************************************"
    $ECHO
    return 1
  fi

  if [ -f "$ROOTPATH/BACKUP_RUNNING" ]; then
    $ECHO
    $ECHO "****************************************************************"
    $ECHO "Last backup didn't finnished yet or didn't finished properly !!!"
    $ECHO "File $ROOTPATH/BACKUP_RUNNING exists. Probably run chkfs."
    $ECHO "Delete unfinished backup, edit @current link to point to correct backup"
    $ECHO "Resolve all issues first. Delete BAKCUP_RUNNING file and run this again."
    $ECHO "****************************************************************"
    $ECHO
    return 1
  fi

  if [ -d "$ROOTPATH/$TODAY_DIR" ]; then
    $ECHO
    $ECHO "***********************************************"
    $ECHO "Today $TODAY_DIR backup already exists!!!"
    $ECHO "***********************************************"
    $ECHO
    return 1
  fi

  if [ -f $RSYNC_ERROR ]; then
    $ECHO
    $ECHO "******************************************"
    $ECHO "Last backup didn't finished properly !!!!!"
    $ECHO "File $RSYNC_ERROR exists. Probably run chkfs."
    $ECHO "Delete unfinished backup, edit @current link to point to correct backup"
    $ECHO "Resolve all issues first. Delete $RSYNC_ERROR file and run this again."
    $ECHO "******************************************"
    $ECHO
    return 1
  fi
}

#name of dir where todays current backup will be stored, can't be defined any sooner, because it needs get_name function
TODAY_DIR=`get_name "d" "now"`

$RM -f $EMAIL_LOG_FILE
$TOUCH $EMAIL_LOG_FILE
$RM -f $LOG_FILE
$TOUCH $LOG_FILE

$ECHO "
------------------------------------------
`$DATE`
" >> $LOG_FILE


sanity_checks 2>&1 | $TEE -a $EMAIL_LOG_FILE $LOG_FILE
EXITING=${PIPESTATUS[0]}


if [ "$EXITING" = "0" ]; then
  $TOUCH $ROOTPATH/BACKUP_RUNNING

  #$ECHO $EMAIL_LOG_FILE
  #$ECHO $LOG_FILE

  $RENICE 15 $$       #Run backup in background priority (20 is idlle,0 normal,-20 very high realtime priority)

  main_backup 2>&1 | $TEE -a $EMAIL_LOG_FILE $LOG_FILE

  END=$($DATE +%s)
  DIFF=$(( $END - $START ))
  let MINS=$DIFF/60
  let HOURS=$MINS/60
  TRVALO="Total time of \"rsync + backup rotations\" = $HOURS hours ( $MINS mins => $DIFF seconds) to finish"
  $ECHO $TRVALO
  $ECHO $TRVALO >> $LOG_FILE
  $ECHO $TRVALO >> $EMAIL_LOG_FILE

  $ECHO ""
  $ECHO "" >> $LOG_FILE
  $ECHO "" >> $EMAIL_LOG_FILE
fi

# Mail the log
if [ ! -z "$ADMIN_EMAIL" ]; then
  if [ ! -f "$NAIL" ]; then
    $ECHO "WARN: $NAIL not found. The log cannot be mailed to "$ADMIN_EMAIL" !!!" >&2
  else
    KEDY=`$DATE  +\%Y-\%m-\%d`
    if [ -z $DEBUG ]; then
      $NAIL -s "Backup Results $3 $KEDY ( $HOURS hours | $MINS mins )" "$ADMIN_EMAIL" < $EMAIL_LOG_FILE
    else 
      $ECHO "This would be emailed to $ADMIN_EMAIL: Backup Results $3 $KEDY ( $HOURS hours | $MINS mins )"
    fi
  fi
fi

if [ "$EXITING" = "0" ]; then
  cat $LOG_FILE >> $FULL_FILE
  cat $LOG_FILE >> $MONTH_FILE
  $CHMOD a+r $LOG_FILE
  $CHMOD a+r $MONTH_FILE
  $CHMOD a+r $FULL_FILE

  $CHMOD a+r $ROOTPATH/backup.lst

  if [ -z $DEBUG ]; then
    $CP $ROOTPATH/backup.lst $ROOTPATH/$TODAY_DIR/backup.lst

    $MV $LOG_FILE $ROOTPATH/$TODAY_DIR/backup_current.log

    if [ "$($DATE -d '+1 day' +%d)" = "01" ]; then
      $MV $MONTH_FILE $ROOTPATH/$TODAY_DIR/backup_month.log
    fi
  fi
  $RM -f $ROOTPATH/BACKUP_RUNNING
fi

$RM -f $EMAIL_LOG_FILE
