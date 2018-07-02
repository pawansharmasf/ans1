#!/bin/sh
IP="$1"
CACHEPATH="$2"

#CACHEPATH=$1
#DOMAIN=web.v2dev.dgadteamdev.com
#IP="10.1.128.164"
#DOMAINPATH=`grep -w $DOMAIN /var/lib/jenkins/sape_scripts/Dispatcher_CacheClear/paths.txt | awk {'print $2'}`

for WEB in $IP
do

if [[ ! $1 =~ ^/$ ]]
then
                if [ ! -z $1 ]
                then
                        printf "Clearing cache for $1\n in $WEB";
                else
                        printf "Invalid Path for cache clearance!\nExiting!";
                        exit 1;
                fi
curl -H "CQ-Action:DELETE" -H "CQ-Handle:$CACHEPATH"  -H"Content-Length: 0" -H "Content-Type: application/octet-stream"  $WEB/dispatcher/invalidate.cache
fi

done

