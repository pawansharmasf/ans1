#!/bin/bash
rm -rf aem_packages/Content_Deployment/packages/*
HOST="$1"
ENV="$2"
PASSWD="$3"
newsource="$4"
dest="$5"
name="$6"
filters="$7"
replicate="$8"
log_file="tmp/install.log"

### Substiting the Varible with the the Jenkins varible name.
tempdate=`date +%Y_%m_%d_%H%M%S`

# DEFINE SOURCE
if [[ -n "$newsource" ]]
then
#	user="${userMap["$newsource"]}"
#	platform="${platformMap["$newsource"]}"
	echo "[$(date +%Y-%m-%d:%H:%M:%S)] > DEPLOY CONTENT FORM $newsource:$HOST" >> $log_file
else
	echo "[$(date +%Y-%m-%d:%H:%M:%S)] > NO SOURCE DEFINE" >> $log_file
	exit 1;
fi

if [[ -n "$dest" ]]
then
#	user_dest="${userMap["$dest"]}"
#	platform_dest="${platformMap["$dest"]}"
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
        curl_output=$(curl -v -u admin:"${PASSWD}" http://$HOST:4502/crx/packmgr/service/.json/etc/package/${name}.zip?cmd=create -d packageName=${name} -d groupName=content-bot)
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
echo ${filters} >> $log_file

        for node in ${filters}
        do
            if [[ $node =~ $regex ]]
            then
                node="${node/.html//jcr:content}"
                curl_output=$(curl -vvv -s -u admin:"${PASSWD}" -Fmode=replace -F"root=${node}" http://$HOST:4502/etc/packages/${c_folder}/${name}${c_suffix}.zip/jcr:content/vlt:definition/filter/f${x})
echo $curl_output >> $log_file
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
        curl_output=$(curl -v -s -u admin:"${PASSWD}" -X POST http://$HOST:4502/crx/packmgr/service/.json/etc/packages/content-bot/${name}.zip?cmd=build)
        if [[ $curl_output = *success\":true* ]]
        then 
			echo "[$(date +%Y-%m-%d:%H:%M:%S)] > PACKAGE BUILT > ${newsource}:${name}" >> $log_file        
        else
			echo "[$(date +%Y-%m-%d:%H:%M:%S)] > PACKAGE BUILD FAILED > ${curl_output}" >> $log_file 
    		exit 1
        fi
        
        mkdir -p aem_packages/Content_Deployment/packages
       curl -s -u admin:"${PASSWD}" http://$HOST:4502/etc/packages/content-bot/${name}.zip > aem_packages/Content_Deployment/packages/${name}.zip
}
create_package
add_package_filters
build
echo "[$(date +%Y-%m-%d:%H:%M:%S) > FINISHED" >> $log_file

exit 0



