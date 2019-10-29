#!/bin/bash
#Rebuild-DNDC
#author: https://github.com/elmerfdz
ver=3.0.6.7-d

#USER CONFIGURABLE VARS - Uncomment VARS
#mastercontname=vpn         #VPN Container name, replace this with your VPN container name - default container name 'vpn'
#ping_count=4               #Number of times you want to ping the ping_ip before the script restarts the MASTER container due to no connectivity, lower number might be too aggressive - default 4
#ping_ip='1.1.1.1'          #IP to ping to test connectivity - default CLOUDFLARE DNS
#ping_ip_alt='8.8.8.8'      #Secondary IP to ping to test connectivity - default GOOGLE DNS.
#mastercontconcheck='yes'   #yes/no to check for MASTER connectivity testing & reboot container - default 'yes'
#sleep_secs=10              #Check for the approximate time it takes for your MASTER container to reboot completely in seconds - default 10s
#unraid_notifications='no'  #Enable Unraid GUI notifications, yes/no
#discord_notifications='no' #Enable Discord notifications, yes/no
#rundockertemplate_script='/script/ParseDockerTemplate.sh' #location of ParseDockerTemplate script - default /tmp/user.scripts/tmpScripts/
#docker_tmpl_loc='/config/docker-templates'

#NON-CONFIGURABLE VARS
contname=''
templatename=''
datetime=$(date +"%T %d-%m-%Y")
mastercontepfile_loc='/config/rebuild-dndc'
#rundockertemplate_script='/script/ParseDockerTemplate.sh' #location of ParseDockerTemplate script - default /tmp/user.scripts/tmpScripts/
#docker_tmpl_loc='/config/docker-templates'
buildcont_cmd="$rundockertemplate_script -v $docker_tmpl_loc/my-$templatename.xml"
mastercontid=$(docker inspect --format="{{.Id}}" $mastercontname)
getmastercontendpointid=$(docker inspect $mastercontname --format="{{ .NetworkSettings.EndpointID }}")
get_container_names=($(docker ps -a --format="{{ .Names }}"))
get_container_ids=($(docker ps -a --format="{{ .ID }}"))


#NOTIFICATIONS
recreatecont_notify_complete()
{
    echo "REBUILDING: ${recreatecont_notify_complete_msg[*]} Completed"
    if [ "$unraid_notifications" == "yes" ]
    then    
        /usr/local/emhttp/webGui/scripts/notify -i "normal"  -s "Rebuild-DNDC"  -d "- REBUILDING: ${recreatecont_notify_complete_msg[*]} Completed "
    fi
    if [ "$discord_notifications" == "yes" ]
    then        
        ./discord-notify.sh "- REBUILDING: ${recreatecont_notify_complete_msg[*]} Completed"  &> /dev/null
    fi
}

recreatecont_notify()
{
    if [ "$getmastercontendpointid" != "$currentendpointid" ]
    then
        echo "Rebuild-DNDC - REBUILDING: $mastercontname container Endpoint doesn't match"
        if [ "$unraid_notifications" == "yes" ]
        then              
            /usr/local/emhttp/webGui/scripts/notify -i "warning" -s "Rebuild-DNDC"  -d "- REBUILDING: $mastercontname container Endpoint doesn't match" 
        fi
        if [ "$discord_notifications" == "yes" ]
        then          
            ./discord-notify.sh "- REBUILDING: $mastercontname container Endpoint doesn't match"  &> /dev/null
        fi
    elif [ "$contnetmode" != "$mastercontid" ]
    then
        echo "Rebuild-DNDC - REBUILDING: ${recreatecont_notify_complete_msg[*]} "
        if [ "$unraid_notifications" == "yes" ]
        then           
            /usr/local/emhttp/webGui/scripts/notify -i "warning"  -s "Rebuild-DNDC"  -d "- REBUILDING: ${recreatecont_notify_complete_msg[*]} "
        fi
        if [ "$discord_notifications" == "yes" ]
        then            
            ./discord-notify.sh "- REBUILDING: ${recreatecont_notify_complete_msg[*]}"  &> /dev/null
        fi
    fi 
}

#MAIN CODE
first_run()
{
    if [ ! -d "$mastercontepfile_loc" ] || [ ! -e "$mastercontepfile_loc/mastercontepid.tmp" ] || [ ! -e "$mastercontepfile_loc/list_inscope_cont_ids.tmp" ] || [ ! -e "$mastercontepfile_loc/list_inscope_cont_tmpl.tmp" ] || [ ! -e "$mastercontepfile_loc/list_inscope_cont_names.tmp" ]  
    then
        mkdir -p "$mastercontepfile_loc" && touch "$mastercontepfile_loc/mastercontepid.tmp" && touch "$mastercontepfile_loc/list_inscope_cont_ids.tmp" && touch "$mastercontepfile_loc/list_inscope_cont_tmpl.tmp" && touch "$mastercontepfile_loc/list_inscope_cont_names.tmp"
        echo "$getmastercontendpointid" > $mastercontepfile_loc/mastercontepid.tmp
        echo "A. FIRST-RUN: SETUP COMPLETE"
        if [ "$unraid_notifications" == "yes" ]
        then              
            /usr/local/emhttp/webGui/scripts/notify -i "normal"  -s "Rebuild-DNDC"  -d "- FIRST-RUN: Setup Complete "
        fi
        if [ "$discord_notifications" == "yes" ]
        then        
            ./discord-notify.sh "Rebuild-DNDC - FIRST-RUN: Setup Complete"  &> /dev/null
        fi
        was_run=1
    elif [ -d "$mastercontepfile_loc" ] && [ -e "$mastercontepfile_loc/mastercontepid.tmp" ] 
    then
        echo "A. SKIPPING: FIRST RUN SETUP" 
        was_run=0
        getmastercontendpointid=$(docker inspect $mastercontname --format="{{ .NetworkSettings.EndpointID }}")
        currentendpointid=$(<$mastercontepfile_loc/mastercontepid.tmp)      
    fi
}

check_masterendpointid()
{
    if [ "$getmastercontendpointid" == "$currentendpointid" ]
    then
        echo "B. SKIPPING: MASTER CONTAINER ENDPOINT IS CURRENT"     
        echo
        inscope_container_vars
    elif [ "$getmastercontendpointid" != "$currentendpointid" ]
    then
        echo "B. ALERT: MASTER container Endpoint doesn't match"
        echo
        inscope_container_vars        
    fi 
}

inscope_container_vars()
{
    echo "C. DETECTING: IN-SCOPE CONTAINERS"
    echo     
    #Cycle & fetch container info
    for ((a=0; a < "${#get_container_names[@]}"; a++)) 
    do
        pull_contnet_ids=($(docker inspect ${get_container_names[$a]} --format="{{ .HostConfig.NetworkMode }}" | sed -e 's/container://g'))
        if [ "$pull_contnet_ids" == "$mastercontid" ]
        then
            list_inscope_cont_tmpl+=($(find $docker_tmpl_loc -type f -iname "*-${get_container_names[$a]}.xml"))
            list_inscope_cont_ids+=(${get_container_ids[$a]})
            list_inscope_contnames+=(${get_container_names[$a]})     
            no=${#list_inscope_contnames[@]}
            echo "$no ${get_container_names[$a]}"
            echo "- ContainerID ${get_container_ids[$a]}"       
            echo "- NetworkID: $pull_contnet_ids"              
            echo "- Template Location: ${list_inscope_cont_tmpl[$b]}"; b=$((b + 1))       
            echo   
        fi 
    done
   
    if [ "${list_inscope_contnames}" == '' ]
    then
        echo "# RESULTS: None in-scope, checking for previous in-scope containers"
        echo
        list_inscope_cont_ids=($(<$mastercontepfile_loc/list_inscope_cont_ids.tmp))
        list_inscope_contnames=($(<$mastercontepfile_loc/list_inscope_cont_names.tmp))
        list_inscope_cont_tmpl=($(<$mastercontepfile_loc/list_inscope_cont_tmpl.tmp))
        if [ "${list_inscope_contnames}" == '' ]
        then
            echo "- No containers in scope."
            echo "- Make sure you have the containers routed through the MASTER are running fine first."
        fi            
    fi    
    #post process inscope containers
    inscope_container_vars_post
 
}

inscope_container_vars_post(){
    echo "${list_inscope_cont_ids[@]}" > $mastercontepfile_loc/list_inscope_cont_ids.tmp;    
    echo "${list_inscope_contnames[@]}" > $mastercontepfile_loc/list_inscope_cont_names.tmp;    
    echo "${list_inscope_cont_tmpl[@]}" > $mastercontepfile_loc/list_inscope_cont_tmpl.tmp;
    if [ "${list_inscope_contnames}" != '' ]
    then
        echo "D. PROCESSING: IN-SCOPE CONTAINERS"
    fi
    echo           
        for ((c=0; c < "${#list_inscope_contnames[@]}"; c++)) 
        do  
        contname=${list_inscope_contnames[$c]}
        CONT_ID=${list_inscope_cont_ids[$c]}              
        CONT_TMPL=${list_inscope_cont_tmpl[$c]}            
        check_networkmodeid
    done
}

check_networkmodeid()
{
    contnetmode=$(docker inspect $contname --format="{{ .HostConfig.NetworkMode }}" | sed -e 's/container://g')
    if [ "$getmastercontendpointid" != "$currentendpointid" ]
    then
        rebuild_mod
        recreatecont_notify_complete_msg+=(${contname[@]})
    elif [ "$contnetmode" == "$mastercontid" ]
    then
        echo "- SKIPPING: $contname NETID = MASTER NETID"
    elif [ "$contnetmode" != "$mastercontid" ]
    then
        echo
        echo "- $contname NetModeID doesn't match with $mastercontname ContID"
        rebuild_mod
    fi
}

rebuild_mod()
{
    buildcont_cmd="$rundockertemplate_script -v $CONT_TMPL"    
    build_stage_var=('Stopping' 'Removing' 'Recreating')
    build_stage_cmd_var=("docker stop $contname" "docker rm $contname" "$buildcont_cmd")

    if [ "$getmastercontendpointid" != "$currentendpointid" ] || [ "$mastercontid" != "$contnetmode" ]
    then
        #Cycle through build commands
            for ((d=0; d < "${#build_stage_var[@]}"; d++)) 
            do
                build_stage=${build_stage_var[$d]}
                build_stage_cmd=${build_stage_cmd_var[$d]}
            echo
            echo "----------------------------"
            echo "  $build_stage $contname   "
            echo "----------------------------"
            echo
            $build_stage_cmd
            done
        was_rebuild=1  
    fi
    
    if [ "$was_run" == 0 ]
    then 
        echo "$getmastercontendpointid" > $mastercontepfile_loc/mastercontepid.tmp
    fi
}

mastercontconnectivity_mod()
{
#Check if MASTER container network has connectivity
if [ "$mastercontconcheck" == "yes" ]
then
    echo "CHECKING"
    docker exec $mastercontname ping -c $ping_count $ping_ip &> /dev/null
    if [ "$?" == 0 ]
    then
        echo "- CONNECTIVITY: OK"
    else
        echo "ALT IP CHECK"
        docker exec $mastercontname ping -c $ping_count $ping_ip_alt &> /dev/null
        if [ "$?" == 0 ]
        then
            echo "- CONNECTIVITY: OK"
        else
            echo "- CONNECTIVITY: BROKEN"
            echo "---- restarting $mastercontname" container
            #docker restart $mastercontname &> /dev/null
            echo "---- $mastercontname restarted"
            echo "---- going to sleep for $sleep_secs seconds"
            sleep $sleep_secs    
        fi    
    fi
fi
}


echo
echo "---------------------------------"
echo "    Rebuild-DNDC v3.0.6.7-d     "
echo "---------------------------------"
echo

echo "-----------------------------------------------------------------------------------"
echo "# MASTER CONTAINER INFO"
echo "- CONTAINER-NAME: $mastercontname"
echo "- ENDPOINT-ID: $getmastercontendpointid"
echo "- NETWORKMODE-ID: $mastercontid"
mastercontconnectivity_mod
echo "-----------------------------------------------------------------------------------"
echo 

#check first run
first_run

#Check MASTER container Endpoint node, immediately rebuild if doesn't match
check_masterendpointid

echo
if [ "$was_rebuild" == 1 ]
then 
    echo "- Re-created: ${recreatecont_notify_complete_msg[@]}"
    recreatecont_notify_complete
fi
echo 
echo "---------------------------------------"
echo " Run Completed @ $datetime  "
echo "---------------------------------------"
echo