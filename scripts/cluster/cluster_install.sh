source /scripts/toolshed/os_detection.sh

check_if_vpn_or_not()
{
    component_vpn_name=${component_vpn_name:-vpn}
    
    ss-display "test if deployment" 1>/dev/null 2>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        export USER_NEW=${USER_NEW:-ifbuser}
        export IP_PARAMETER=${IP_PARAMETER:-hostname}
    else
        check_vpn=$(ss-get ss:groups | grep -c ":$component_vpn_name")
        category=$(ss-get ss:category)
        if [ "$check_vpn" != "0" ]; then            
            if [ "$category" == "Deployment" ]; then
                vpn_multiplicity=$(ss-get $component_vpn_name:multiplicity)
                if [ "$vpn_multiplicity" != "0" ]; then
                    USER_NEW=${USER_NEW:-ifbuser}
                    if [ "$(echo $(ss-get net.services.enable) | grep '"vpn"' | wc -l)" == "1" ]; then
                        IP_PARAMETER=vpn.address
                        ss-set net.services.enable "[\"vpn\"]"
                    else
                        ss-set net.services.enable "[]"
                        IP_PARAMETER=hostname
                    fi
                else
                    USER_NEW=${USER_NEW:-ifbuser}
                    ss-set net.services.enable "[]"
                    IP_PARAMETER=hostname
                fi
            else
                USER_NEW=${USER_NEW:-ifbuser}
                ss-set net.services.enable "[]"
                IP_PARAMETER=hostname
            fi
        else
            USER_NEW=${USER_NEW:-ifbuser}
            IP_PARAMETER=hostname
        fi
    fi
    
    #url.service display when vpn is on
    if [ $IP_PARAMETER == "vpn.address" ]; then
        #MASTER_IP=$(ss-get $MASTER_HOSTNAME:$IP_PARAMETER)
        IP_VPN=$(ss-get $component_vpn_name:hostname)
        url="ssh://$USER_NEW@$IP_VPN"
        #ss-set url.ssh "${url}"
        ss-set url.service "${url}"
        ss-set ss:url.service "${url}"
    fi
    
    WORKDIR=/root/mydisk
    mkdir -p $WORKDIR
    chmod 750 /root
    chmod 775 $WORKDIR
    
    ss-set allowed_components "$(echo $(ss-get allowed_components) | sed 's|ifbuser|'$USER_NEW'|g' )"
}

initiate_master_cluster()
{
    check_if_vpn_or_not
    
    ID=1
    
    HOSTIP=$(ss-get $IP_PARAMETER)

    if [ "$category" == "Deployment" ]; then
        ss-set master.nodename $(ss-get nodename)
        HOSTNAME=$(ss-get nodename)-$ID

        ss-get --timeout=3600 slave.nodename
        SLAVE_NAME=$(ss-get slave.nodename)
    else
        HOSTNAME=machine-$ID
    fi
    if [ "$(ss-get $component_vpn_name:edugain.enable)" == "false" ] ; then
        ssh_root=/root/.ssh
        ssh_user=/home/$USER_NEW/.ssh
        if [ ! -f $ssh_user/authorized_keys ]; then
            mkdir -p $ssh_user
            touch $ssh_user/authorized_keys
            chmod 700 $ssh_user
            chmod 600 $ssh_user/authorized_keys
            chown $USER_NEW:$USER_NEW $ssh_user/authorized_keys
        fi
        cat $ssh_root/authorized_keys >> $ssh_user/authorized_keys
        msg_info "ssh key of root imported to $USER_NEW."
    fi

    HOSTNAME=$(echo $HOSTNAME | sed "s|_|-|g")
    echo "$HOSTNAME" > /etc/hostname
    hostname $HOSTNAME   
}

initiate_slave_cluster()
{
    check_if_vpn_or_not
    
    ID=1
    
    if [ "$category" != "Deployment" ]; then
        ss-abort "You need to deploy with a master!!!"
    fi

    ss-set slave.nodename $(ss-get nodename)
    SLAVE_HOSTNAME=$(ss-get nodename).$(ss-get id)
    SLAVE_HOSTNAME_SAFE=$(ss-get nodename)-$(ss-get id)

    SLAVE_IP=$(ss-get $SLAVE_HOSTNAME:$IP_PARAMETER)

    ss-get --timeout=3600 master.nodename
    MASTER_HOSTNAME=$(ss-get master.nodename)
    MASTER_HOSTNAME_SAFE=$MASTER_HOSTNAME-$ID

    MASTER_IP=$(ss-get $MASTER_HOSTNAME:$IP_PARAMETER)

    SLAVE_HOSTNAME_SAFE=$(echo $SLAVE_HOSTNAME_SAFE | sed "s|_|-|g")
    echo "$SLAVE_HOSTNAME_SAFE" > /etc/hostname
    hostname $SLAVE_HOSTNAME_SAFE
}

initiate_install_edugain()
{
    apt-get install -y python python-dev python-pip libpam-python
    pip install scriptine
    pip install requests[security]
    wget -O - https://raw.githubusercontent.com/cyclone-project/cyclone-python-pam/master/setup.sh | sed 's/~/\/tmp\//g' | sh
    wget -O /lib/security/cyclone_pam.py https://raw.githubusercontent.com/bryan-brancotte/cyclone-python-pam/patch-5/lib/security/cyclone_pam.py
    echo "{
      \"ports\":[[20000, 25000] ]
    }" > /lib/security/cyclone_config
    cp /etc/pam.d/sshd /etc/pam.d/sshd.bak
    cat /etc/pam.d/sshd.bak | sed 's/ auth /auth /g' | sed 's/auth /#auth /g' | sed 's/##auth /auth /g' > /etc/pam.d/sshd
    service ssh restart
}

initiate_install_edugain_ubuntu16()
{
    #apt-get install -y python python-dev python-pip libpam-python
    
    # Toogle to install xPra
    #export XPRA_INSTALL=true

    ## INSTALL CYCLONE PAM
    wget -O - https://raw.githubusercontent.com/cyclone-project/cyclone-python-pam/V2/setup.sh | sh > /root/cyclone-install.log
    

#sed -ie '/BASE_URI =/i\
#global s\
#s = socket\.socket(socket\.AF_INET, socket\.SOCK_DGRAM)\
#s\.connect(("8\.8\.8\.8", 80))\
#' /usr/local/bin/cyclone_pam.py
#    sed -i 's|host_ip = .*|host_ip = s\.getsockname()[0]|' /usr/local/bin/cyclone_pam.py

    # Load default configuration
    echo "# CUSTOM NUVLA CONFIGURATION" >> /etc/cyclone/cyclone.conf
    echo "OIDC_HOST = https://federation.cyclone-project.eu" >> /etc/cyclone/cyclone.conf
    echo "PORTS = 20000-25000" >> /etc/cyclone/cyclone.conf
    
    if [ "$(echo $(ss-get cloudservice) | grep exoscale | wc -l)" == "1" ]; then
        EXO_HOSTNAME=$(ss-get hostname)
        echo "HOSTNAME_OPENSTACK = $EXO_HOSTNAME" >> /etc/cyclone/cyclone.conf
    elif [ "$(ss-get cloudservice)" == "ifb-genouest-genostack" ]; then
        echo "HOSTNAME_OPENSTACK = http://169.254.169.254/latest/meta-data/local-ipv4" >> /etc/cyclone/cyclone.conf
    elif [ "$(ss-get cloudservice)" == "cyclone-fr2" ]; then
        echo "HOSTNAME_OPENSTACK = http://169.254.169.254/latest/meta-data/local-ipv4" >> /etc/cyclone/cyclone.conf
    else
        echo "HOSTNAME_OPENSTACK = http://169.254.169.254/latest/meta-data/public-ipv4" >> /etc/cyclone/cyclone.conf
    fi
    
    # Clean up installation files
    #cd ~ && rm -rf cyclone-pam    
}

install_edugain_ubuntu16()
{
    EDUGAIN_OTHERS_USERS=$(ss-get edugain.others.users)
    if [ -z "$EDUGAIN_OTHERS_USERS" -o $( echo "$EDUGAIN_OTHERS_USERS" | grep -c "@") == 0 ]; then
        msg_info "No new user to add in federation proxy Eudgain ."
    else 
        # Set good syntax
        others=$(echo ", $EDUGAIN_OTHERS_USERS" | sed -e 's/[^ ],/ ,/' -e 's/,[^ ]/, /' )
    fi
    
    if [ "$(echo $(ss-get cloudservice) | grep exoscale | wc -l)" == "1" ]; then
        OPENSTACK_HOSTNAME=$(ss-get hostname)
    elif [ "$(ss-get cloudservice)" == "ifb-genouest-genostack" ]; then
        OPENSTACK_HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
    elif [ "$(ss-get cloudservice)" == "cyclone-fr2" ]; then
        OPENSTACK_HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
    else
        OPENSTACK_HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
    fi

    echo "REALM = $(ss-get federated_identity_realm)" >> /etc/cyclone/cyclone.conf
    echo "CLIENT_ID = $(ss-get federated_identity_client_id)" >> /etc/cyclone/cyclone.conf
    echo "CLIENT_SECRET = $(ss-get federated_identity_client_secret)" >> /etc/cyclone/cyclone.conf
    if [ ! "$OPENSTACK_HOSTNAME" == "" ]; then
        echo "HOSTNAME = $OPENSTACK_HOSTNAME" >> /etc/cyclone/cyclone.conf
    fi

    cd /scripts/

    NEW_USER="$(ss-get edugain_username)"

    source /scripts/edugain_access_tool_shed.sh --dry-run
    source /scripts/allows_other_to_access_me.sh --dry-run

    auto_gen_users
    gen_key_for_user $NEW_USER
    echo "EMAIL = $(echo_owner_email) $others" > /home/$NEW_USER/.cyclone
    publish_pubkey
    allow_others
    
    source /scripts/populate_hosts_with_components_name_and_ips.sh --dry-run
    component_vpn_name=${component_vpn_name:-vpn}
    check_vpn=$(ss-get ss:groups | grep -c ":$component_vpn_name")
    if [ "$check_vpn" != "0" ]; then
        if [ "$category" == "Deployment" ]; then            
            if [ "$(echo $(ss-get net.services.enable) | grep vpn | wc -l)" == "1" ]; then
                populate_hosts_with_components_name_and_ips vpn.address
            else
                populate_hosts_with_components_name_and_ips hostname
            fi
        else
            populate_hosts_with_components_name_and_ips hostname
        fi
    else
        populate_hosts_with_components_name_and_ips hostname
    fi

    if [ "$(ss-get cloudservice)" == "cyclone-fr2" ]; then
        # set the service url to SSH url
        url=$(echo -n "$(ss-get url.ssh)" | sed 's/root/ubuntu/g')
        ss-set url.ssh "${url}"
        ss-set url.service "${url}"
        ss-set ss:url.service "${url}"
    fi

    url="ssh://$NEW_USER@$(ss-get hostname)"
    old_ssh="$(ss-get url.ssh)"
    ss-set url.ssh "${url}"
    ss-set url.service "[ssh-edu]${url}, ${old_ssh}"
    ss-set ss:url.service "[ssh-edu]${url}, ${old_ssh}"

    # Execute rc.local for the first time manually
    /etc/rc.local
}
    
install_edugain()
{
    source /scripts/edugain_access_tool_shed.sh --dry-run
    source /scripts/allows_other_to_access_me.sh --dry-run
    #auto_gen_users
    gen_key_for_user $USER_NEW
    init_edugain_acces_to_user $USER_NEW
    add_email_for_edugain_acces_to_user $(echo_owner_email) $USER_NEW
    #publish_pubkey
    #allow_others
    #source /scripts/populate_hosts_with_components_name_and_ips.sh --dry-run
    #populate_hosts_with_components_name_and_ips $IP_PARAMETER
    
    service ssh restart
    #echo $(hostname -I | sed 's/ /\n/g' | head -n 1) > /etc/hostname 
    
    #hostname -F /etc/hostname
    
    url="ssh://$USER_NEW@$(ss-get hostname)"
    ss-set url.ssh "${url}"
    ss-set url.service "${url}"
    ss-set ss:url.service "${url}"
    
    echo "FederatedEntryPoint overlay deploy done"
}

msg_info()
{
    ss-display "test if deployment" 1>/dev/null 2>/dev/null
    ret=$?
    if [ $ret -ne 0 ]; then
        echo -e "$@"
    else
        echo -e "$@"
        ss-display "$@"
    fi
}

install_federation_proxy()
{
    msg_info "Extract username and usermail"
    
    EDUGAIN_OTHERS_USERS=$(ss-get edugain.others.users)
    
    username=$(cat /opt/slipstream/client/bin/slipstream.context | grep username | sed 's/username = //g')
    cat /opt/slipstream/client/bin/slipstream.context | grep cookie | sed 's/cookie = //g' > /root/.slipstream-cookie
    ss-user-get $username 1> /root/user.xml

    user_mail=$(cat /root/user.xml | sed 's/ /\n/g' | grep email= | sed 's/email=//g' | sed 's/"//g')
    ss-display "$username has mail $user_mail"

    ss-set user.mail.edugain $user_mail
    
    if [ -z "$EDUGAIN_OTHERS_USERS" -o $( echo "$EDUGAIN_OTHERS_USERS" | grep -c "@") == 0 ]; then
        msg_info "No new user to add in federation proxy Edugain ."
    else 
        # Set good syntax
        others=$(echo ", $EDUGAIN_OTHERS_USERS" | sed -e 's/[^ ],/ ,/' -e 's/,[^ ]/, /' )
    fi
        
    if [ ! -d /ifb/federated-filtering-proxy-with-docker/ ]
    then
            mkdir -p /ifb/federated-filtering-proxy-with-docker/
            cd /ifb/federated-filtering-proxy-with-docker/
            git clone https://github.com/cyclone-project/federated-filtering-proxy-with-docker .
        
        
            echo "cyclone: $user_mail $others" > apache_groups
            # iptables -I INPUT 1 -p tcp -i docker0 -m tcp --dport 8080 -j ACCEPT

            msg_info "docker proxy ready to start"

            chmod a+rx *.sh
    fi

    msg_info "run federated proxy"


    cd /ifb/federated-filtering-proxy-with-docker/
    ./startFilteringProxy.sh | tee /var/log/run_federate_proxy.log
}

user_add()
{
    getent passwd $USER_NEW > /dev/null
    user_missing=$?
    if [ "$user_missing" != "0" ]; then
        useradd --create-home -u 666 $USER_NEW --shell /bin/bash
    else
        usermod -u 666 $USER_NEW
        groupmod -g 666 $USER_NEW
    fi
    ln -s /root/mydisk/ /home/$USER_NEW/work
    usermod -aG root $USER_NEW
    
    msg_info ""
    msg_info "$USER_NEW created for launch job"
}

user_sudoers(){
	if grep -q $USER_NEW "/etc/sudoers"; then 
		echo "$USER_NEW ready"
	else 
		echo -e "$USER_NEW\tALL=(ALL)\tNOPASSWD:ALL" >> /etc/sudoers
	fi
}

selinux_config(){
    setenforce 1
    setsebool -P use_nfs_home_dirs=true
}

check_ip()
{
    NETWORK_MODE=$(ss-get network)
    if [ "$NETWORK_MODE" == "Public" ]; then
        PUBLIC_IP=$(ss-get $IP_PARAMETER)
        #ss-set hostname "${PRIVATE_IP}"
        HOSTIP=$(echo $(hostname -I | sed 's/ /\n/g' | head -n 1))
        SLAVE_IP=$HOSTIP
        sed -i "s|$PUBLIC_IP|$HOSTIP|g" /etc/hosts
    else
        PUBLIC_IP=$(ss-get $IP_PARAMETER)
        HOSTIP=$(ss-get $IP_PARAMETER)
        SLAVE_IP=$HOSTIP
    fi
    ss-set ip.ready "$HOSTIP"
}

check_ip_slave_for_master()
{
    url="ssh://$USER_NEW@$PUBLIC_IP"
    ss-set url.service "${url}"
    ss-set ss:url.service "${url}"
    
    for (( i=1; i <= $(ss-get $SLAVE_NAME:multiplicity); i++ )); do
        msg_info "Waiting ip of slave to be ready."
        ss-get --timeout=3600 $SLAVE_NAME.$i:ip.ready
        PUBLIC_SLAVE_IP=$(ss-get $SLAVE_NAME.$i:$IP_PARAMETER)
        SLAVE_IP=$(ss-get $SLAVE_NAME.$i:ip.ready)
        sed -i "s|$PUBLIC_SLAVE_IP|$SLAVE_IP|g" /etc/hosts
    done
}

check_ip_master_for_slave()
{
    msg_info "Waiting ip of master to be ready."
    ss-get --timeout=3600 $MASTER_HOSTNAME:ip.ready
    url=$(ss-get $MASTER_HOSTNAME:url.service)
    PUBLIC_IP_MASTER=$(ss-get $MASTER_HOSTNAME:$IP_PARAMETER)
    MASTER_IP=$(ss-get $MASTER_HOSTNAME:ip.ready)
    sed -i "s|$PUBLIC_IP_MASTER|$MASTER_IP|g" /etc/hosts
    ss-set url.service "${url}"
    ss-set ss:url.service "${url}"    
}

#####
# NFS
#####

NFS_start()
{
	msg_info "Starting NFS..."
    if iscentos 7; then
        systemctl enable nfs-server
        systemctl start nfs-server
        systemctl reload nfs-server
    elif iscentos 6; then
        chkconfig nfs on 
	    service nfs start
        service nfs reload
    fi
    if isubuntu; then
	    service nfs-kernel-server start
        service nfs-kernel-server reload
    fi
    exportfs -av
    ss-set nfs.ready "true"
    msg_info "NFS is started."
}

NFS_ready(){
    ss-get --timeout=3600 $MASTER_HOSTNAME:nfs.ready
    nfs_ready=$(ss-get $MASTER_HOSTNAME:nfs.ready)
    msg_info "Waiting NFS to be ready."
	while [ "$nfs_ready" == "false" ]
	do
		sleep 10;
		nfs_ready=$(ss-get $MASTER_HOSTNAME:nfs.ready)
	done
}

# exporting NFS share from master
NFS_export()
{
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a directory in argument !"
    else    
        EXPORT_DIR=$1

        if [ ! -d "$EXPORT_DIR" ]; then
            msg_info "$EXPORT_DIR doesn't exist !"
        else    
            msg_info "Exporting NFS share of $EXPORT_DIR..."
	
            EXPORTS_FILE=/etc/exports
            if grep -q --perl-regex "$EXPORT_DIR\t" $EXPORTS_FILE; then 
        		echo "$EXPORT_DIR ready"
        	else 
                echo -ne "$EXPORT_DIR\t" >> $EXPORTS_FILE
            fi
            for (( i=1; i <= $(ss-get $SLAVE_NAME:multiplicity); i++ )); do
                if [ $IP_PARAMETER == "hostname" ]; then
                    node_host=$(ss-get $SLAVE_NAME.$i:ip.ready)
                else
                    node_host=$(ss-get $SLAVE_NAME.$i:$IP_PARAMETER)
                fi
                if grep -q $EXPORT_DIR.*$node_host $EXPORTS_FILE; then 
        		    echo "$node_host ready"
        	    else
                    echo -ne "$node_host(rw,sync,no_subtree_check,no_root_squash) " >> $EXPORTS_FILE
                fi
            done
            echo "" >> $EXPORTS_FILE # last for a newline
	
        	msg_info "$EXPORT_DIR is exported."
        fi
    fi
}

# Mounting directory
NFS_mount()
{
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a directory in argument !"
    else    
        MOUNT_DIR=$1
    
        if [ ! -d "$MOUNT_DIR" ]; then
            msg_info "$MOUNT_DIR doesn't exist !"
        else    
            msg_info "Mounting $MOUNT_DIR..."
    
            umount $MOUNT_DIR
            mount $MASTER_IP:$MOUNT_DIR $MOUNT_DIR 2>/tmp/mount_error_message.txt
            ret=$?
            msg_info "$(cat /tmp/mount_error_message.txt)"
     
            if [ $ret -ne 0 ]; then
                ss-abort "$(cat /tmp/mount_error_message.txt)"
            else
                 msg_info "$MOUNT_DIR is mounted"
            fi
        fi
    fi
}

## ADD SLAVES
UNSET_parameters(){
    ss-set nfs.ready "false"
    ss-set sge.ready "false"
}

NFS_export_add()
{
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a directory in argument !"
    else    
        EXPORT_DIR=$1

        if [ ! -d "$EXPORT_DIR" ]; then
            msg_info "$EXPORT_DIR doesn't exist !"
        else    
            msg_info "Exporting NFS share of $EXPORT_DIR..."
	
            EXPORTS_FILE=/etc/exports
            if grep -q --perl-regex "$EXPORT_DIR\t" $EXPORTS_FILE; then 
        		echo "$EXPORT_DIR ready"
        	else 
                echo -ne "$EXPORT_DIR\t" >> $EXPORTS_FILE
                echo -ne "$SLAVE_IP(rw,sync,no_subtree_check,no_root_squash) " >> $EXPORTS_FILE
                echo "" >> $EXPORTS_FILE # last for a newline
            fi
            if grep -q $EXPORT_DIR.*$SLAVE_IP $EXPORTS_FILE; then 
        	    echo "$SLAVE_IP ready"
            else
                WD=$(echo $EXPORT_DIR | sed 's|\/|\\\/|g')
                sed -i '/'$WD'/s/$/\t'$SLAVE_IP'(rw,sync,no_subtree_check,no_root_squash)/' $EXPORTS_FILE
            fi
	
        	msg_info "$EXPORT_DIR is exported."
        fi
    fi
}

make_file_test_sge()
{
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a directory in argument !"
    else    
        TESTDIR=$1
        mkdir -p $TESTDIR
        chmod 775 $TESTDIR
        echo "for i in {1..50}" > $TESTDIR/qsub_test.sh
        echo "    do" >> $TESTDIR/qsub_test.sh
        echo "        len=\$(shuf -i 1-10 -n 1)" >> $TESTDIR/qsub_test.sh
        echo "        echo \"sleep \$len\" > /tmp/sleep\$i-\$len.sh" >> $TESTDIR/qsub_test.sh
        echo "    qsub /tmp/sleep\$i-\$len.sh" >> $TESTDIR/qsub_test.sh
        echo "done" >> $TESTDIR/qsub_test.sh
        echo "echo \"run 'watch -n 1 qstat -f' to monitor the computation\"" >> $TESTDIR/qsub_test.sh
        chmod 755 $TESTDIR/qsub_test.sh
    fi
}

make_file_test_slurm()
{
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a directory in argument !"
    else
        file_name=submit    
        TESTDIR=$1
        mkdir -p $TESTDIR
        chmod 775 $TESTDIR
        echo "#!/bin/bash" > $TESTDIR/$file_name.sh
        echo "#" >> $TESTDIR/$file_name.sh
        echo "#SBATCH --output=res.txt" >> $TESTDIR/$file_name.sh
        echo "for i in {1..50}" >> $TESTDIR/$file_name.sh
        echo "    do" >> $TESTDIR/$file_name.sh
        echo "        len=\$(shuf -i 1-10 -n 1)" >> $TESTDIR/$file_name.sh
        echo "        echo \"#\$i : sleep \$len\" >> res.txt" >> $TESTDIR/$file_name.sh
        echo "        srun sleep \$len" >> $TESTDIR/$file_name.sh
        echo "done" >> $TESTDIR/$file_name.sh
        echo "wait" >> $TESTDIR/$file_name.sh
        chmod 755 $TESTDIR/$file_name.sh
    fi
}

clean_docker()
{
    apt-get purge -y docker*
    apt-get autoremove -y --purge docker*
    apt-get autoclean
    rm -rf /var/lib/docker
    rm /etc/apparmor.d/docker
    if grep -q docker /etc/group
    then
        groupdel docker
    else
        echo "group not exits"
    fi
}

post_install_edugain(){
    if isubuntu; then
        check_if_vpn_or_not
        if [ $IP_PARAMETER == "hostname" ]; then
            pip install -r /scripts/requirements.txt
            if isubuntu 14; then
                initiate_install_edugain
            elif isubuntu 16; then
                initiate_install_edugain_ubuntu16
            fi
        fi
    fi
}