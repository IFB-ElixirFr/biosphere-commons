check_json_tool_shed(){
    if [ ! -e /scripts/json_tool_shed.py ]; then
        mkdir -p /scripts/
        wget https://raw.githubusercontent.com/IFB-ElixirFr/biosphere-commons/master/scripts/json_tool_shed.py  -O /scripts/json_tool_shed.py
        chmod a+rx -R /scripts/
    fi
}

get_ids_for_component(){
    category=$(ss-get ss:category)
    if [ "$category" == "Deployment" ]; then
        if [ "$(ss-get $1:multiplicity)" == "0" ]; then
            echo ""
        else
            echo $(ss-get --timeout 1200 $1:ids)
        fi
    else
       echo "1"
    fi
    #ids=$(ss-get --timeout 1200 $name:ids)
    #if [ "$ids" == "" ]; then
    #    ss-abort "Failed to retrieve ids of $name on $(ss-get hostname)"
    #    return 1
    #fi
}

get_available_components() {
    available_components=""
    category=$(ss-get ss:category)
    if [ "$category" == "Deployment" ]; then
        for name in `ss-get ss:groups | sed 's/, /,/g' | sed 's/,/\n/g' | cut -d':' -f2`; do     
            if [ "$(ss-get $name:multiplicity)" != "0" ]; then
                available_components="$available_components,$name"
            fi
        done
    else
        available_components="machine"
    fi
    echo "$available_components" | sed 's/^,//g'
}

get_users_that_i_should_have(){
    users=""
    category=$(ss-get ss:category)
    if [ "$category" == "Deployment" ]; then
        nodename=$(ss-get nodename)
        for name in `echo "$(get_available_components)" | sed 's/,/\n/g' | cut -d':' -f2`; do 
            ids=$(get_ids_for_component $name)
            id=$(echo $ids | sed 's/,/\n/g' | head -n 1);
            users="$users
$(ss-get $name.$id:allowed_components | grep -v none | sed 's/, /,/g' | sed 's/,/\n/g' | grep "$nodename" | cut -d: -f2)"
        done  
    fi
    users="$users
$(ss-get allowed_components | grep -v none | sed 's/, /,/g' | sed 's/,/\n/g' | cut -d: -f3)"
    echo $users | sort | uniq | grep -v "^$"
}

gen_key_for_user_and_allows_hosts(){
    ss-display "Setting ssh key for $1 to hosts $2"
    echo "Setting ssh key for $1 to hosts $2"
    if [ "$1" == "" ]; then
        return
    fi
    # getent passwd $1 > /dev/null
    user_missing=$(grep -c "^$1:" /etc/passwd)
    if [ "$user_missing" == "0" ]; then
        useradd --shell /bin/bash --create-home $1
    else
        mkhomedir_helper $1
    fi
    usr_home=$(getent passwd $1 | cut -d: -f6)
    if [ ! -e $usr_home/.ssh/ ]; then
        mkdir $usr_home/.ssh/
        chmod 700 $usr_home/.ssh/
    fi
    if [ ! -e $usr_home/.ssh/id_rsa ]; then
        ssh-keygen -f $usr_home/.ssh/id_rsa -t rsa -N ''
        ssh-keygen -y -f $usr_home/.ssh/id_rsa > $usr_home/.ssh/id_rsa.pub
        chmod 700 $usr_home/.ssh/id_rsa
    fi
    category=$(ss-get ss:category)
    if [ "$category" == "Deployment" ]; then
        hostnames_in_cluster="$2"
        echo "#$(date)">>$usr_home/.ssh/config
        sed -i "/#GEN_HOSTS_CONFIG/,+4d" $usr_home/.ssh/config
        echo "Host $hostnames_in_cluster #GEN_HOSTS_CONFIG
        ConnectTimeout 30
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        
        ">>$usr_home/.ssh/config
        chmod -R 700 $usr_home/.ssh/
        chmod -R 700 $usr_home/.ssh/
    fi
    chown $1:$1 -R $usr_home/.ssh/
    echo "Setting ssh key for $1 done"
}

get_hostnames_in_cluster(){
    hostnames_in_cluster=" "
    for name in `echo "$(get_available_components)" | sed 's/, /,/g' | sed 's/,/\n/g' | cut -d':' -f2`; do 
        ids=$(get_ids_for_component $name)
        if [ "$ids" == "1" ]; then
            hostnames_in_cluster="$hostnames_in_cluster $name"
        else
            for i in $(echo $ids | sed 's/,/\n/g'); do
                hostnames_in_cluster="$hostnames_in_cluster $name-$i $name.$i"
            done
        fi
    done
    echo  $hostnames_in_cluster
}

gen_key_for_user(){
    gen_key_for_user_and_allows_hosts "$1" "$(get_hostnames_in_cluster)"
}

publish_pubkey(){
    ss-display "Fetching already published pubkey(s)"
    check_json_tool_shed
    #pubkey=$(ss-get --timeout 1200 pubkey)
    pubkey="{}"
    for user in $(cat /etc/passwd | grep -v nologin |cut -d: -f1 ); do 
        pubkey_path="$(getent passwd $user | cut -d: -f6)/.ssh/id_rsa.pub"
        if [ -e $pubkey_path ]; then 
            echo "Publishing pubkey of $user"
            pubkey=$(/scripts/json_tool_shed.py add_in_json "$pubkey" "$user" "u'$(cat $pubkey_path)'" --print-value)
        else
            echo "Publishing pubkey of $user impossible, $pubkey_path is missing "
        fi
    done
    ss-set pubkey "$pubkey"
}

get_ip_for_component(){
    echo $(getent hosts $(ss-get $1:hostname) | awk '{ print $1 }' | head -n 1)
    #echo $(ss-get $1:vpn.address)
}

allow_others(){
    ss-display "Allowing others to access to me"
    echo "Allowing others to access to me"
    check_json_tool_shed
    category=$(ss-get ss:category)
    for name in `ss-get allowed_components | sed 's/, /,/g' | sed 's/,/\n/g' `; do 
        if [ "$name" == "none" ]; then
            echo -e "not needed in fact"
        else
            #IFS=:
            #ary=($name)
            #name=${ary[0]}
            #remote_user=${ary[1]:-root}
            #local_user=${ary[2]:-root}
            remote_user=$(echo $name| cut -d':' -f2)
            local_user=$(echo $name| cut -d':' -f3)
            name=$(echo $name| cut -d':' -f1)
            remote_user=${remote_user:-root}
            local_user=${local_user:-root}
            ids=$(get_ids_for_component $name)
            for i in $(echo $ids | sed 's/,/\n/g'); do
                echo -e "Allowing $remote_user of $name.$i to ssh me on user $local_user"
                if [ "$category" == "Deployment" ]; then
                    pubkey=$(ss-get --timeout 1200 $name.$i:pubkey)
                else
                    pubkey=$(ss-get --timeout 1200 $name:pubkey)
                fi
                pubkey=$(/scripts/json_tool_shed.py find_in_json "$pubkey" "$remote_user" --print-values)
                if [ "$pubkey" == "" ]; then
                    ss-abort "Failed to retrieve pubkey of user $remote_user from host $name.$i on $(ss-get hostname)"
                    return 1
                fi
                if [ "$local_user" == "root" ]; then
                    DOT_SSH=~/.ssh
                else
                    if [ "$(getent passwd $local_user | wc -l)" == "0" ]; then
                        useradd --create-home $local_user --shell /bin/bash
                    else
                        mkhomedir_helper $local_user
                    fi
                    DOT_SSH="$(getent passwd $local_user | cut -d: -f6)/.ssh"
                    if [ ! -d $DOT_SSH ]; then
                        mkdir $DOT_SSH
                    fi
                    chmod 700 $DOT_SSH
                fi
                LOCAL_USER_HOME_DIR="$(getent passwd $local_user | cut -d: -f6)"
                msg="#component $name.$i can ssh me"
                if [ "$(grep "$msg" $DOT_SSH/authorized_keys 2>/dev/null | wc -l)" == "0" ]; then
                    echo $msg >> $DOT_SSH/authorized_keys
                    echo "$pubkey" >> $DOT_SSH/authorized_keys
                    ls -laHi $DOT_SSH
                    echo -e "Allowing $remote_user of $name.$i to ssh me on user $local_user done"
                fi
                chmod 700 "$LOCAL_USER_HOME_DIR/.ssh/authorized_keys"
                chown -R $local_user:$local_user "$LOCAL_USER_HOME_DIR"
            done
        fi
    done
    echo "Allowing others to access to me done"
}

auto_gen_users(){
    hostnames_in_cluster="$(get_hostnames_in_cluster)"
    category=$(ss-get ss:category)
    if [ "$category" == "Deployment" ]; then
        nodename=$(ss-get nodename)
    else
        nodename="machine"
    fi
    for user in $(get_users_that_i_should_have); do 
        gen_key_for_user_and_allows_hosts "$user" "$hostnames_in_cluster"
        for host in $(echo $hostnames_in_cluster | sed 's/ /\n/g' | grep -v '\-[0-9]*$' ); do 
            target_users=$(echo $(ss-get $host:allowed_components) | sed 's/, /\n/g' | grep "^$nodename:$user:" | cut -d: -f3)
            target_users_count=$(echo $target_users | grep -v "^$" | sed 's/ /\n/g' | wc -l)
            ssh_config="$(cat /etc/passwd | grep "^$user:" | cut -d: -f6)/.ssh/config"
            for real_host in $(echo $hostnames_in_cluster | sed 's/ /\n/g' | grep "$host" ); do 
                sed -i "/Host $real_host #END/,+2d" $ssh_config
            done
            if [ "$target_users_count" == "1" ]; then
                for real_host in $(echo $hostnames_in_cluster | sed 's/ /\n/g' | grep "$host" ); do 
                    echo "Host $real_host #END
                    user $target_users
                    ">> $ssh_config
                done
            fi
        done
    done
}

if [ "$1" == "--dry-run" ]; then
    echo "function loaded"
    echo "You can do:"
    echo "    source /scripts/allows_other_to_access_me.sh --dry-run "
    echo "    auto_gen_users"
    echo "    gen_key_for_user alice"
    echo "    gen_key_for_user bob"
    echo "    gen_key_for_user charlie"
    echo "    publish_pubkey"
    echo "    allow_others"
else
    auto_gen_users
    publish_pubkey
    allow_others
fi
