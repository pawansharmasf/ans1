#!/bin/bash
## To run the offline compaction on author instance

#mail_recipient="asethi11@sapient.com"
#mail_from="offline-compaction@sapient.com"
#mkdir /app/compaction-files
########### Declaring Variables, Please edit this sectiononly ############
#env=lb_qa1-author
port="$1"
instance="$2"
instancepath="$3"
servicename="$4"
user="$5"
compactionfilespath=$instancepath/compaction-files
touch $compactionfilespath/author-log.txt
touch $compactionfilespath/author-nohup.out
touch $compactionfilespath/author-nohup.txt
touch $compactionfilespath/compaction-log.txt
logfile=$compactionfilespath/author-log.txt
##heap size to execute th compaction ###
MEM_ARG="$6"
nohupfile=$compactionfilespath/author-nohup.out
nohuptxtfile=$compactionfilespath/author-nohup.txt

############## Variables for backup #######################

backup_loc="/app/backup/$instance"
del_date=$(date '+%F' --date="-7 days")
backup_dir="$backup_loc/crx-quickstart.$(date '+%F')/"
backuplogfile=$backup_loc/backup.log

#####Deleting old logs and last week AEM backup ########


mkdir -p $backup_loc

rm -f $nohupfile
rm -f $nohuptxtfile
rm -f $logfile
rm -f $backuplogfile
rm -f $compactionfilespath/compaction-log.txt

##### Starting the backup ###########################

#echo "Starting the rsync at `date`." >> $backuplogfile

# rsync -avz --delete --stats --exclude="logs/*" $instancepath $backup_dir 2>&1 >> $backuplogfile
# rsync -avz --delete --stats --exclude="logs/*" $instancepath $backup_dir 2>&1 >> $backuplogfile

#echo "Completed the rsync before stopping the instance at `date`." >> $backuplogfile

###### completed the running backup ###########

############### Checking repository size and stopping the instance #############

sizebefore=`du -sh $instancepath/crx-quickstart/repository/ | awk '{print $1}'`

echo "Repository Size before offline compression $sizebefore" >> $logfile
echo "" >> $logfile

pid=`ps -ef | grep -v grep | grep Dsling | grep $port |awk '{print $2}'`

#echo "$env offline compaction is starting and the instance will be down for next 10-30 minutes depending on the repositoty size" | mailx -S smtp=smtp.dxide.com -s "Offline compaction starting on $env"  -r $mail_from $mail_recipient


#echo "$env offline compaction is starting and the instance will be down for next 10-30 minutes depending on the repositoty size"

echo "Stopped the instance for compaction $(date '+On %F at %T') EST" >>  $logfile
echo "" >> $logfile

sudo service $servicename stop

sleep 360

 check_process=`ps -ef | grep -v grep | grep Dsling | grep $port |awk '{print $2}'|wc -l`

 if [ $check_process -eq 1 ]
then
  sudo service $servicename stop
 sleep 360
check_process=`ps -ef | grep -v grep | grep Dsling | grep $port |awk '{print $2}'|wc -l`
if [ $check_process -eq 1 ]
then
echo "Not able to stop the instance using init scripting , so exiting from the script" >>  $logfile
echo "" >> $logfile
#mailx -S smtp=smtp.dxide.com  -s "Offline compaction is not happened in $env"  -r $mail_from $mail_recipient  < $logfile
exit 1
 fi
fi
# sync; sysctl -w vm.drop_caches=3

####################### Instance stop completed ###########################

###################### Taking final rsync after instance stop ###########

#echo "Starting the rsync after stopping the instance at `date`." >> $backuplogfile

# rsync -avz --delete --stats --exclude="logs/*" $instancepath $backup_dir 2>&1 >> $backuplogfile
# rsync -avz --delete --stats --exclude="logs/*" $instancepath $backup_dir 2>&1 >> $backuplogfile

#echo "Completed the rsync after stopping the instance at `date`." >> $backuplogfile
########################  Backup completed  ##########################


################  Starting the compaction  #####################

echo "Started the compaction $(date '+On %F at %T') EST" >>  $logfile
echo "" >> $logfile

cd $compactionfilespath

/usr/bin/bash -x  $compactionfilespath/compatch.sh $MEM_ARG $compactionfilespath $instancepath >> $nohupfile

echo "Compaction Completed $(date '+On %F at %T') EST" >>  $logfile
echo "" >> $logfile

echo "Changed the ownership for files and folders to "$instance" user" >>  $logfile
echo "" >> $logfile

sudo chown $user:$user $instancepath -R


##############  Compaction Completed   ##################

##############   Starting the instance and sending the alert  #############

echo "Starting the instance after compaction $(date '+On %F at %T') EST" >>  $logfile

sudo service $servicename start

sleep 360

echo "Start completed after compaction $(date '+On %F at %T') EST" >>  $logfile
echo "" >> $logfile

newpid=`ps -ef | grep -v grep | grep Dsling | grep $port |awk '{print $2}'|wc -l`

if [ $newpid -ne 1 ]

        then

#                echo "Failed to start $env after compaction , Please start the instance manually" | mailx -S smtp=smtp.dxide.com -s "CRITICAL ALERT- Instance start failed for $env" -r $mail_from $mail_recipient
                exit
        fi


sizeafter=`du -sh $instancepath/crx-quickstart/repository/ | awk '{print $1}'`

echo "Repository Size after compression $sizeafter" >> $logfile
echo "" >> $logfile
echo "" >> $logfile
echo "" >> $logfile
echo "Kindly refer the attachment for compaction Logs" >> $logfile

mv $nohupfile $nohuptxtfile
#mailx -S smtp=smtp.dxide.com -a /app/compaction-files/compaction-log.txt -s "Offline compaction is completed in $env"  -r $mail_from $mail_recipient  < $logfile

############################  Script completed ##########################

