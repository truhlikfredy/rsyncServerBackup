#!/bin/bash

TEE=/usr/bin/tee
RENICE=/usr/bin/renice
PS=/bin/ps
ECHO=/bin/echo
TIME=/usr/bin/time
BASENAME=/usr/bin/basename
PWD=/bin/pwd
RHASH=/usr/bin/rhash
LRZTAR=/usr/bin/lrztar

pack_everything() {
  extension_log="tar.lrz.log"
  
  orig=`$PWD`
  cd $1
  #directory=`$BASENAME $1`
  directory=$2
  #renice doesn't work as well if multiple threads are running and only it will renice 1 of the threads
  #  $RENICE 19 $$       #Run backup in background priority (20 is idlle,0 normal,-20 very high realtime priority)

  $ECHO "==========================================" > $directory.$extension_log
  $ECHO "Compressing backup $1/$2 (name of backup $2.tar.lrz) ... " | $TEE -a $directory.$extension_log

  #compress directory -p1 will force into single threaded but it will improve compression ratio, in my case just 1MB difference
  #but on dual core NAS i don't want to load fully whole system, with single thread the compressing is more effective and
  #rest of the system still responding
  ($TIME $LRZTAR -q -f -p1 -L9 $directory ) >> $directory.$extension_log 2>&1

  $ECHO "==========================================" >> $directory.$extension_log
  $ECHO "Calculating checksum..." | $TEE -a $directory.$extension_log
  $ECHO "==========================================" >> $directory.$extension_log

  #calculate checksums
  ($TIME $RHASH --printf="crc32=%{crc32}\nmd5=%{md5}\nsha1=%{sha1}\nsha-256=%{sha-256}\n" $directory.tar.lrz ) >> $directory.$extension_log 2>&1
  
  mv $directory.tar.lrz z_packed/$directory.tar.lrz
  mv $directory.$extension_log z_packed/$directory.$extension_log
  cd $orig
}


sanity_checks() {
  if [ ! -f "$ECHO" ]; then
    echo "Path to echo command ($ECHO) doesn't exist."
    exit 1
  fi

  if [ ! -f "$TEE" ] || [ ! -f "$RENICE" ] || [ ! -f "$PS" ] || [ ! -f "$TIME" ] || [ ! -f "$BASENAME" ] || [ ! -f "$PWD" ]; then
    $ECHO "Paths to tools (tee renice ps time basename pwd) aren't setup properly." 
    exit 1
  fi   
  if [ ! -f "$RHASH" ] || [ ! -f "$LRZTAR" ]; then
    $ECHO "Paths to tools (rhash lrztar)  aren't setup properly." 
    exit 1
  fi   

  if [ "$#" -le "1" ] ; then
    $ECHO "Usage: compress.sh pathToRootFolder bakcupFolderName" 
    $ECHO "  eg.: compress.sh /path/where/store server-backup-2015" 
    exit 1
  fi 

}

sanity_checks $@
pack_everything $@