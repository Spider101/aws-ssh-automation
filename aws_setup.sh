#!/bin/bash

function log_and_exec(){
	printf "\n%s ..\n" "$1"
	eval $2
	printf "Done!\n"
}

function get_instance_username(){
    shopt -s nocasematch
    case $1 in
        *ubuntu*)
            echo 'ubuntu' 
            ;;
        *centos*)
            echo 'centos'
            ;;
        *)
            echo 'ec2-user'
            ;;
    esac
}

function build_ssh_host(){
    hostname=$(sed -e 's/^"//' -e 's/"$//' <<< "$(query_instance "${1}" 'PublicDnsName')")

    if [[ -z `grep "${1}" $HOME/.ssh/config` ]]
    then
        echo -e '\nAdding new entry in config file..\n'
        image_id=$(sed -e 's/^"//' -e 's/"$//' <<< "$(query_instance "${1}" 'ImageId')")
        image_name=$(aws ec2 describe-images --image-ids ${image_id} | jq '.Images[].Name')
        user=$(get_instance_username "${image_name}")
        
        read -p "Enter path to access key: " access_key_path
        echo
        ssh_config_entry="Host ${1}\n\tHostname ${hostname}\n\tUser ${user}\n\tIdentityFile ${access_key_path}\n"
        echo -e "${ssh_config_entry}" >> $HOME/.ssh/config
        echo -e 'Done\n'
    else
        echo -e '\nAdjusting entry in config file..\n'
        sed -i "/${1}/ {n; s|\(Hostname \).*|\1${hostname}|;}" $HOME/.ssh/config
        echo -e 'Done\n'
    fi
}
function query_instance(){
    metadata=$(aws ec2 describe-instances --filter "Name=tag:Name,Values=${1}")
    echo "${metadata}" | jq ".Reservations[].Instances[].${2}"
}

function start_instance(){
    status=1
    instance_status=$(sed -e 's/^"//' -e 's/"$//' <<<"$(query_instance "${1}" 'State.Name')")
    if [ "$instance_status" == 'running' ]
    then
        [[ -z $2  ]] && echo -e 'Instance is already running!'
        [[ ! -z $2 ]] && status=0
    elif [ "$instance_status" != 'stopped' ]
    then
        echo -e 'Instance is not in a state to be run. Please try again later!'
    else
        [[ ! -z $2 ]] && echo -e "\nStarting instance '${1}' as it was in stopped state"
        instance_id=$(sed -e 's/^"//' -e 's/"$//' <<< "$(query_instance "${1}" 'InstanceId')")
        aws ec2 start-instances --instance-ids $instance_id | jq '.StartingInstances[].CurrentState.Name'
        i=0
        spinner="-\|/"
        until [ "${instance_status}" == 'running' ]
        do
            i=$(( (i+1) %4  ))
            printf "\rPlease wait ${spinner:$i:1}"
            instance_status=$(sed -e 's/^"//' -e 's/"$//' <<<"$(query_instance "${1}" 'State.Name')")
        done
        echo
        [[ ! -z $2 ]] && echo -e "Instance '${1}' is ${instance_status}. Continuing to connect to it..\n" && status=0
    fi
    return $status
}

function stop_instance(){
    instance_status=$(sed -e 's/^"//' -e 's/"$//' <<<"$(query_instance "${1}" 'State.Name')")
    if [ "$instance_status" == 'stopped' ]
    then
        echo -e 'Instance is already stopped!'
    elif [ "$instance_status" != 'running' ]
    then
        echo -e 'Instance is not in a state to be stopped. Please try again later!'
    else
        instance_id=$(sed -e 's/^"//' -e 's/"$//' <<< "$(query_instance "${1}" 'InstanceId')")
        aws ec2 stop-instances --instance-ids $instance_id | jq '.StoppingInstances[].CurrentState.Name'
        i=0
        spinner="-\|/"
        until [ "${instance_status}" == 'stopped' ]
        do
            i=$(( (i+1) %4  ))
            printf "\rPlease wait ${spinner:$i:1}"
            instance_status=$(sed -e 's/^"//' -e 's/"$//' <<<"$(query_instance "${1}" 'State.Name')")
        done
        echo
    fi
}

function connect_to_instance(){
    start_instance "${1}" 'suppress-log'
    if [ $? -eq 0 ] 
    then
        log_message='Correcting ssh config file'
        log_and_exec "${log_message}" "build_ssh_host \"${1}\" "
        ssh ${1}
    else
        echo -e "\nSomething went wrong in trying to check status/starting the instance\n"
    fi
}

function menu(){
    menu_list=("Query Instance" "Start Instance"  "Stop Instance" "Connect to Instance" 'Quit')
    PS3='Choose action: '
    select action in "${menu_list[@]}"
    do
        case $action in
            'Query Instance')
                echo
                read -p 'Enter name of instance to query: ' instance_name
                read -p 'Enter property to query instance: ' property
                log_message="Querying ${instance_name} for ${property} property"
                log_and_exec "${log_message}" "printf \"\'${property}\': \'$(query_instance ${instance_name} ${property})\' \n\""
                echo
                return 1
                ;;
            'Start Instance')
                echo
                read -p 'Enter name of instance: ' instance_name
                log_message="Starting instance '${instance_name}'"
                log_and_exec "${log_message}" "start_instance ${instance_name}"
                echo
                return 1
                ;;
            'Stop Instance')
                echo
                read -p 'Enter name of instance: ' instance_name
                log_message="Stopping instance '${instance_name}'"
                log_and_exec "${log_message}" "stop_instance ${instance_name}"
                echo
                return 1
                ;;
            'Connect to Instance')
                echo
                read -p 'Enter name of instance: ' instance_name
                log_message="Connecting to '${instance_name}'"
                log_and_exec "${log_message}" "connect_to_instance ${instance_name}"
                echo
                return 1
                ;;
 
            Quit)
                return 0
                ;;
            *)
                echo -e 'Invalid choice. Please choose again\n'
                ;;
        esac
    done

}

function run(){
    is_complete=1
    while [[ $is_complete -gt 0 ]]
    do
        menu
        is_complete=$?
    done
    echo "Thank you for using the aws setup!"
}

run
