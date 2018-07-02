#!/usr/bin/env bash

####
####
####
####


trap printout SIGINT                                                     #you get back the shell color when ctrl+c is pressed
printout() {
echo -en ${NC}
exit
}







PROJECT_NAME=${PROJECT_NAME:-}
RUN_MODE=${RUN_MODE:-}

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"
__root="$(cd "$(dirname "${__dir}")" && pwd)"

binDir="${__dir}"/bin


. "${binDir}"/messages
. "${binDir}"/colors
. "${binDir}"/inventory
. "${binDir}"/setenv
. "${binDir}"/info
. "${binDir}"/getOsFlavor
. "${binDir}"/installAnsible
. "${binDir}"/checkoutFrameworkCode
. "${binDir}"/installAEM
. "${binDir}"/prepareEnvironment
. "${binDir}"/setupJenkins
. "${binDir}"/urlEncode
. "${binDir}"/setupTomcatJenkins

loadInventory
getOsFlavour
preInstallChecks
#echo -e "${Black}Hello ${DarkGray}THERE${LightRed}  here ${Green}HELLO again ${LightGreen} Light Green socks aren't sexy ${Orange} neither are Orange  "
echo -en ${LightRed}
echo "Please enter Project Name"$'\r'
read PROJECT_NAME

if [ -z ${PROJECT_NAME} ];then
  echo "Project Name cannot be empty" ; exit
fi

echo -en "$LightGreen"


function newAMSInv(){

echo -en "$White"
prepareEnvironment
#displayUpdateOptions

}


#function installNew()
#{
#getOsFlavour
#preInstallChecks
##installAnsible
##checkoutFrameworkCode
##getUserChoice
#getGenericInstallData
#}

function setupJenkins()
{
echo -en "$Yellow"
getUserJenkinsInfo
#installJenkins
setupansiblejobs
}
function setupGIT()
{
setupandpushGit
}
function setupTomcatJenkins()
{
getUserTomcatInfo
setupJenkinsJobs
}

echo -e "\nEnter a choice: \n"
select RUN_MODE in "${FRAMEWORK_RUN_MODE[@]}"
do
    case ${RUN_MODE} in
#        "InstallNew")
#            echo "Coming Soon....."
#            #installNew
#            break
#            ;;
        "Create new inventory")
            echo "You have chosen to create new inventory"
	    newAMSInv
            break
            ;;
        "Setup Jenkins and GIT repo for ansible")
	    read -p "setup jenkins [yes for setting up jenkins on tomcat / No for installing jenkins using yum ]" user_choice

	    if [[ $user_choice =~ ^[Yy] ]]
	    then
		 echo "You have chosen to setup Jenkins on Tomcat"
                 setupTomcatJenkins
            else

		    echo "You have chosen to setup GIT Repo alongwith jenkins for ansible"
		    setupJenkins
            	   
            fi
		 break
		  ;;
        "Setup GIT repo for ansible")
            echo "You have chosen to setup GIT Repo for ansible"
	    setupGIT
            break
	    ;;
	       
        "Quit")
            break
            ;;
        *) echo invalid option ;;
    esac
done
echo -en "$White"
