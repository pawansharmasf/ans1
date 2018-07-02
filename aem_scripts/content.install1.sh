#!/bin/bash
#rm -rf /app/User-Creation/alcs-devops-cm/ansible/aem_scripts/Content_Deployment/backups/*
HOST="$1"
ENV="$2"
PASSWD="$3"
newsource="$4"
dest="$5"
name="$6"
filters="$7"
replicate="$8"
log_file="tmp/deploy.log"

### Substiting the Varible with the the Jenkins varible name.
tempdate=`date +%Y_%m_%d_%H%M%S`

# DEFINE SOURCE
if [[ -n "$newsource" ]]
then
#       user="${userMap["$newsource"]}"
#       platform="${platformMap["$newsource"]}"
        echo "[$(date +%Y-%m-%d:%H:%M:%S)] > DEPLOY CONTENT FORM $newsource:$HOST" >> $log_file
else
        echo "[$(date +%Y-%m-%d:%H:%M:%S)] > NO SOURCE DEFINE" >> $log_file
        exit 1;
fi

if [[ -n "$dest" ]]
then
#       user_dest="${userMap["$dest"]}"
#       platform_dest="${platformMap["$dest"]}"
        echo "[$(date +%Y-%m-%d:%H:%M:%S)] > DEPLOY CONTENT TO $dest:$HOST" >> $log_file
else
echo "[$(date +%Y-%m-%d:%H:%M:%S)] > NO SOURCE DEFINE" >> $log_file
fi

echo "[$(date +%Y-%m-%d:%H:%M:%S)] > DEPLOY CONTENT FROM $newsource to $dest, name:$name, nodes : \n $filters" >> $log_file
if [[ -z "$newsource" || -z "$name" || -z "$filters" ]]
then
        echo "[$(date +%Y-%m-%d:%H:%M:%S)] > ERROR > at least 1 params is missing (newsource, name, dest)" >> $log_file
        exit 2
fi



create_package() {
                echo "[$(date +%Y-%m-%d:%H:%M:%S)] > CREATE PACKAGE" >> $log_file
        curl_output=$(curl -v -u Deployadmin:"${PASSWD}" http://$HOST:4502/crx/packmgr/service/.json/etc/package/${name}.zip?cmd=create -d packageName=${name} -d groupName=content-bot)
        if [[ $curl_output = *success\":true* ]]
        then
                echo "[$(date +%Y-%m-%d:%H:%M:%S)] > CREATED PACKAGE:${newsource}:${name}" >> $log_file
        else
                        echo "[$(date +%Y-%m-%d:%H:%M:%S)] > ERROR : $curl_output" >> $log_file
                exit 1
        fi
}

add_package_filters() {
   # c_user=${user}
   # c_platform=${platform}
    c_folder=content-bot
    c_suffix=''
    add_filters
}
add_filters(){
        x=0
                echo "[$(date +%Y-%m-%d:%H:%M:%S)] > SETTING PACKAGE" >> $log_file
        regex='^/etc/.*$|^/content/.*$'
        for node in ${filters}
        do
            if [[ $node =~ $regex ]]
            then
                node="${node/.html//jcr:content}"
                curl -v -s -u Deployadmin:"${PASSWD}" -Fmode=replace -F"root=${node}" http://$HOST:4502/etc/packages/${c_folder}/${name}${c_suffix}.zip/jcr:content/vlt:definition/filter/f${x}
                                echo "[$(date +%Y-%m-%d:%H:%M:%S)] > NODE > $node ($x)" >> $log_file
                x=$(($x+1))
                if [ $x -gt 20 ]
                then
                                        exit 0
                fi
            else
                           echo "[$(date +%Y-%m-%d:%H:%M:%S)] > NODE INVALID > $node" >> $log_file
                           exit 0
            fi
        done
}

build(){
        curl_output=$(curl -s -u Deployadmin:"${PASSWD}" -X POST http://$HOST:4502/crx/packmgr/service/.json/etc/packages/content-bot/${name}.zip?cmd=build)
        if [[ $curl_output = *success\":true* ]]
        then
                        echo "[$(date +%Y-%m-%d:%H:%M:%S)] > PACKAGE BUILT > ${newsource}:${name}" >> $log_file
        else
                        echo "[$(date +%Y-%m-%d:%H:%M:%S)] > PACKAGE BUILD FAILED > ${curl_output}" >> $log_file
                exit 1
fi

        mkdir -p /app/User-Creation/alcs-devops-cm/ansible/aem_scripts/Content_Deployment/packages
        curl -s -u Deployadmin:"${PASSWD}" http://$HOST:4502/etc/packages/content-bot/${name}.zip > /app/User-Creation/alcs-devops-cm/ansible/aem_scripts/Content_Deployment/packages/${name}.zip
}		
create_backup() {
        curl_output=$(curl -s -u Deployadmin:"${PASSWD}" http://$HOST:4502/crx/packmgr/service/.json/etc/package/${name}_Backup.zip?cmd=create -d packageName=${name}_Backup -d groupName=backup-bot -vv)
        if [[ $curl_output = *success\":true* ]]
        then 
			echo "[$(date +%Y-%m-%d:%H:%M:%S)] > BACKUP CREATED > ${newsource}:${name}" >> $log_file
        else
        	echo "[$(date +%Y-%m-%d:%H:%M:%S) >  BACKUP CREATION FAILED > ${curl_output}" >> $log_file
    		exit 1
        fi
        curl -s -u Deployadmin:"${PASSWD}" -F"jcr:primaryType=nt:unstructured"  http://$HOST:4502/etc/packages/backup-bot/${name}_Backup.zip/jcr:content/vlt:definition/filter > /dev/null 2>&1
}

add_backup_filters() {
	RET="${RET}\nADDING NODE"
#    c_user=${user_dest}
 #   c_platform=${platform_dest}
    c_folder=backup-bot
    c_suffix='_Backup'
    add_filters
}

build_backup(){
        curl_output=$(curl -v -u Deployadmin:"${PASSWD}" -X POST http://$HOST:4502/crx/packmgr/service/.json/etc/packages/backup-bot/${name}_Backup.zip?cmd=build)
        if [[ $curl_output = *success\":true* ]]
        then 
			echo "[$(date +%Y-%m-%d:%H:%M:%S) > BACKUP BUILT > ${newsource}:${name}" >> $log_file
        else
        	echo "[$(date +%Y-%m-%d:%H:%M:%S) >  BACKUP BUILD FAILED > ${curl_output}" >> $log_file
    		exit 1
        fi

		mkdir -p /app/User-Creation/alcs-devops-cm/ansible/aem_scripts/Content_Deployment/backups
        curl -s -u Deployadmin:"${PASSWD}" http://$HOST:4502/etc/packages/backup-bot/${name}_Backup.zip > /app/User-Creation/alcs-devops-cm/ansible/aem_scripts/Content_Deployment/backups/${name}_Backup.zip
}

upload() {
	echo "[$(date +%Y-%m-%d:%H:%M:%S) > UPLOADING PACKAGE > ${newsource}:${name}" >> $log_file
    curl_output=$(curl -s -u admin:"${PASSWD}" -F package=@aem_packages/Content_Deployment/packages/${name}.zip -F force=true http://$HOST:4506/crx/packmgr/service/.json/?cmd=upload)
    if [[ $curl_output = *success\":true* ]]
    then 
    	echo "[$(date +%Y-%m-%d:%H:%M:%S) > FILE UPLOADED > ${newsource}:${name}" >> $log_file

    else
       	echo "[$(date +%Y-%m-%d:%H:%M:%S) > FILE UPLOAD FAILED > ${curl_output}" >> $log_file
		exit 1
    fi    
}

install_package() {

   	echo "[$(date +%Y-%m-%d:%H:%M:%S) > INSALLING PACKAGE > ${newsource}:${name}" >> $log_file
	   
    curl_output=$(curl -s -u admin:"${PASSWD}" -X POST http://$HOST:4506/crx/packmgr/service/console.html/etc/packages/content-bot/${name}.zip?cmd=dryrun | grep '<b>[A-Z-]<')

    curl_output="${curl_output//<span class=\"-\"><b>/ }"
    curl_output="${curl_output//<span class=\"U\"><b>/ }"
    curl_output="${curl_output//<span class=\"D\"><b>/ }"
    curl_output="${curl_output//<span class=\"A\"><b>/ }"
    curl_output="${curl_output//<span class=\"R\"><b>/ }"
    curl_output="${curl_output//<\/b>&nbsp;/ }"
    curl_output="${curl_output//<\/span><br>/ }"
	echo "[$(date +%Y-%m-%d:%H:%M:%S) > DRY RUN" >> $log_file
	echo "$curl_output" >> $log_file

   	echo "[$(date +%Y-%m-%d:%H:%M:%S) > INSALL" >> $log_file

    
 curl_output=$(curl -s -u admin:"${PASSWD}" -X POST http://$HOST:4506/crx/packmgr/service/.json/etc/packages/content-bot/${name}.zip?cmd=install)

    if [[ $curl_output = *success\":true* ]]
    then
		echo "[$(date +%Y-%m-%d:%H:%M:%S) > INSTALL DONE" >> $log_file
    else
    	echo "[$(date +%Y-%m-%d:%H:%M:%S) > INSTALL FAILED" >> $log_file
		echo "[$(date +%Y-%m-%d:%H:%M:%S) > ERROR > ${curl_output}" >> $log_file
        exit 1
    fi
    if [[ $replicate == true ]]
    then
    curl_output=$(curl -s -u admin:"${PASSWD}" -X POST http://$HOST:4506/crx/packmgr/service/.json/etc/packages/content-bot/${name}.zip?cmd=replicate)
    if [[ $curl_output = *success\":true* ]]
    then
		echo "[$(date +%Y-%m-%d:%H:%M:%S) > REPLICATION DONE" >> $log_file
    else
    	echo "[$(date +%Y-%m-%d:%H:%M:%S) > REPLICATION FAILED" >> $log_file
		echo "[$(date +%Y-%m-%d:%H:%M:%S) > ERROR > ${curl_output}" >> $log_file
        exit 1
    fi
    else
        echo "Replication not done by user"

    fi
}
if [ "$dest" != "none" ]
then
   # create_backup
   # add_backup_filters
    #build_backup
    upload
    install_package
   #purge_cache
fi

echo "[$(date +%Y-%m-%d:%H:%M:%S) > FINISHED" >> $log_file

exit 0
		
