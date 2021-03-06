source /scripts/cluster/cluster_install.sh

initiate_variable_global_torque()
{
    PBS_TEMP_DIR=/tmp/torque
    MAUI_TEMP_DIR=/tmp/maui
    INSTALL_DIR=/opt
    PBS_ROOT_DIR=$INSTALL_DIR/torque
    mauidir=$INSTALL_DIR/maui
    maui_bin=/usr/local/maui/bin
    maui_sbin=/usr/local/maui/sbin
    ID=1
}

initiate_master_torque()
{
    initiate_variable_global_torque
    
    #torque or maui
    scheduler_type=${scheduler_type:-torque}
    
    HOSTIP=$(ss-get $IP_PARAMETER)

    if [ "$category" == "Deployment" ]; then
        ss-set master.nodename $(ss-get nodename)
        HOSTNAME=$(ss-get nodename)-$ID

        ss-get --timeout=3600 slave.nodename
        SLAVE_NAME=$(ss-get slave.nodename)
        #echo $HOSTIP $HOSTNAME |  tee -a /etc/hosts
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

initiate_slave_torque()
{    
    initiate_variable_global_torque
    
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
    
    hostname $SLAVE_HOSTNAME_SAFE
}

package_centos_torque(){
    yum update -y
    yum install -y wget csh bzip2 libtool openssl-devel libxml2-devel boost-devel gcc gcc-c++ autoconf automake make git
    
    #torque or maui
    scheduler_type=${scheduler_type:-torque}
    
    if [ ! -e $PBS_ROOT_DIR ]; then
        git clone https://github.com/adaptivecomputing/torque $PBS_TEMP_DIR
        mkdir -p $INSTALL_DIR
        cp -rf $PBS_TEMP_DIR $INSTALL_DIR
        chmod a+rx -R $PBS_ROOT_DIR
    fi
    
    if [ $scheduler_type == "maui" ]; then
        if [ ! -e $mauidir ]; then
            git clone https://github.com/jbarber/maui $MAUI_TEMP_DIR
            mkdir -p $INSTALL_DIR
            cp -rf $MAUI_TEMP_DIR $INSTALL_DIR
            chmod a+rx -R $mauidir
        fi
        echo 'export PATH=$PATH:'$mauidir'/bin' > /etc/profile.d/maui.sh
    fi
    
    cd $PBS_ROOT_DIR
    ./autogen.sh    
}

package_ubuntu_torque(){
    apt-get update -y
    apt-get install -y wget csh bzip2 build-essential autotools-dev automake libtool openssl libboost-dev gcc g++ gpp kcc libssl-dev libxml2-dev libtool openssh-server make git nfs-kernel-server pvm-dev
    
    #mkdir -p $PBS_TEMP_DIR
    #mkdir -p $PBS_ROOT_DIR
    #wget -O $PBS_TEMP_DIR/index.php?wpfb_dl=3170 http://www.adaptivecomputing.com/index.php?wpfb_dl=3170
    #cd $PBS_TEMP_DIR
    #tar -xzf index.php?wpfb_dl=3170
    #cp -rf torque-6.1.0/* $PBS_ROOT_DIR/
    #rm -rf $PBS_TEMP_DIR/index.php?wpfb_dl=3170
    
    #torque or maui
    scheduler_type=${scheduler_type:-torque}
    
    if [ $scheduler_type == "maui" ]; then
        if [ ! -e $mauidir ]; then
            git clone https://github.com/jbarber/maui $MAUI_TEMP_DIR
            mkdir -p $INSTALL_DIR
            cp -rf $MAUI_TEMP_DIR $INSTALL_DIR
            chmod a+rx -R $mauidir
        fi    
        echo 'export PATH=$PATH:'$mauidir'/bin' > /etc/profile.d/maui.sh
    fi
}

package_torque(){
    initiate_variable_global_torque
    
    if iscentos; then
        package_centos_torque
    elif isubuntu; then
        package_ubuntu_torque
    else
        ss-abort "centos or ubuntu only!!!"
    fi
}

check_if_torque_is_ready_on_master(){
    ss-get --timeout=3600 $MASTER_HOSTNAME:pbs.ready
    pbs_ready=$(ss-get $MASTER_HOSTNAME:pbs.ready)
    msg_info "Waiting TORQUE to be ready."
	while [ "$pbs_ready" == "false" ]
	do
		sleep 10;
		pbs_ready=$(ss-get $MASTER_HOSTNAME:pbs.ready)
	done
}

install_centos_torque_master(){
	msg_info ""
	msg_info "Installing server host..."
	SPOOL_DIR=/var/spool/torque
    if iscentos 7; then
    	INIT=/usr/lib/systemd/system
    	CONTRIB=$PBS_ROOT_DIR/contrib/systemd
    	TRQAUTHD=trqauthd.service
    	PBS_SERVER=pbs_server.service
    	PBS_MOM=pbs_mom.service
        PBS_SCHED=pbs_sched.service
    elif iscentos 6; then
    	INIT=/etc/init.d
    	CONTRIB=$PBS_ROOT_DIR/contrib/init.d
    	TRQAUTHD=trqauthd
    	PBS_SERVER=pbs_server
    	PBS_MOM=pbs_mom
        PBS_SCHED=pbs_sched
    fi    
    
    cd $PBS_ROOT_DIR
	if [ -d "$SPOOL_DIR" ]; then
		echo "torque ready"
	else
		./configure;make;make install;
		echo `hostname` > $SPOOL_DIR/server_name
		cp $CONTRIB/$TRQAUTHD $INIT/
	
		if iscentos 7; then
			systemctl enable $TRQAUTHD
			echo /usr/local/lib > /etc/ld.so.conf.d/torque.conf
			ldconfig
			systemctl restart $TRQAUTHD
		elif iscentos 6; then
			chkconfig --add $TRQAUTHD
			echo /usr/local/lib > /etc/ld.so.conf.d/torque.conf
			ldconfig
			service $TRQAUTHD restart
		fi
	
		qterm
		echo "y" | ./torque.setup root
	    qterm
	fi
    
	echo $HOSTNAME > $SPOOL_DIR/server_priv/nodes
	
	if [ "$category" == "Deployment" ]; then
        node_multiplicity=$(ss-get $SLAVE_NAME:multiplicity)
        if [ "$node_multiplicity" != "0" ]; then
        	for i in $(echo "$(ss-get $SLAVE_NAME:ids)" | sed 's/,/\n/g'); do
        	
        	    if [ $IP_PARAMETER == "hostname" ]; then
                    node_host=$(ss-get $SLAVE_NAME.$i:ip.ready)
                else
                    node_host=$(ss-get $SLAVE_NAME.$i:$IP_PARAMETER)
                fi
        	    node_name=$SLAVE_NAME-$i
        	    echo $node_name >> $SPOOL_DIR/server_priv/nodes
            done
        fi
	fi	
	
	cp $CONTRIB/$PBS_SERVER $INIT/
	
	if iscentos 7 ; then
		systemctl enable $PBS_SERVER
		systemctl restart $PBS_SERVER
        #pbs_server -t create
	elif iscentos 6; then
		chkconfig --add $PBS_SERVER	
		service $PBS_SERVER restart
        #pbs_server -t create
	fi

	make packages
	
	SERVER_DOMAIN=".france-bioinformatique.fr"
	#qmgr -c 'set server submit_hosts = '$HOSTNAME''
	qmgr -c 'set server allow_node_submit=true'
	qmgr -c 'set server managers = root@*'$SERVER_DOMAIN''
	qmgr -c 'set server managers += '$USER_NEW'@*'$SERVER_DOMAIN''
	qmgr -c 'set server operators = root@*'$SERVER_DOMAIN''
	qmgr -c 'set server operators += '$USER_NEW'@*'$SERVER_DOMAIN''
	qmgr -c 'set server scheduling=True'
	qmgr -c 'set server auto_node_np = True'
    
	msg_info ""
	msg_info "Installing compute nodes..."
	if [ "$category" == "Deployment" ]; then
        compute_node=$(ss-get compute.enable)
        if [ "$compute_node" != "false" ]; then
	        Install_exec_torque_centos
        fi
        node_multiplicity=$(ss-get $SLAVE_NAME:multiplicity)
        if [ "$node_multiplicity" != "0" ]; then
        	for i in $(echo "$(ss-get $SLAVE_NAME:ids)" | sed 's/,/\n/g'); do
        	#for (( i=1; i <= $(ss-get $SLAVE_NAME:multiplicity); i++ )); do
        	
        	    if [ $IP_PARAMETER == "hostname" ]; then
                    node_host=$(ss-get $SLAVE_NAME.$i:ip.ready)
                else
                    node_host=$(ss-get $SLAVE_NAME.$i:$IP_PARAMETER)
                fi
        	    node_name=$SLAVE_NAME-$i

        		scp -prq -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null torque-package-mom-linux-x86_64.sh $node_host:$PBS_ROOT_DIR
        		scp -prq -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null torque-package-clients-linux-x86_64.sh $node_host:$PBS_ROOT_DIR
		
        		if iscentos 7; then
        			INIT_NODE=/usr/lib/systemd/system
        			CONTRIB_NODE=$PBS_ROOT_DIR/contrib/systemd
        			PBS_MOM_NODE=pbs_mom.service
        		else
        			INIT_NODE=/etc/init.d
        			CONTRIB_NODE=$PBS_ROOT_DIR/contrib/init.d
        			PBS_MOM_NODE=pbs_mom
        		fi
			
        		scp -prq -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $CONTRIB_NODE/$PBS_MOM_NODE $node_host:$INIT_NODE/
                
                qmgr -c 'set server submit_hosts += '$node_name''
            done
        fi
    else
        Install_exec_torque_centos
    fi
    
    if [ $scheduler_type == "maui" ]; then
    	msg_info ""
    	msg_info "Installing maui..."
    	if [ -d "$MAUI_TEMP_DIR/bin" ]; then
    		echo "maui ready"
    	else
    		$maui_bin/schedctl -k &
    		cd $MAUI_TEMP_DIR;./configure;make;make install;
    	fi
    	$maui_bin/schedctl -k &
    	$maui_sbin/maui &
    else
        cp $CONTRIB/$PBS_SCHED $INIT/
        systemctl enable $PBS_SCHED
        systemctl start $PBS_SCHED
    fi
    
    ss-set pbs.ready "true"
    
    msg_info "PBS is installed and configured."
}

install_exec_torque_centos(){
    cp $CONTRIB/$PBS_MOM $INIT/
    ./torque-package-mom-linux-x86_64.sh --install
    ./torque-package-clients-linux-x86_64.sh --install
    ldconfig
    if [ $RELEASEVER == "7" ] ; then
    	systemctl enable $PBS_MOM
    	systemctl restart $PBS_MOM
    else
    	chkconfig --add $PBS_MOM	
    	service $PBS_MOM restart
    fi
    qmgr -c 'set server submit_hosts = '$HOSTNAME''
}

install_centos_torque_slave(){
	msg_info ""
	echo "Configuring compute nodes..."
	cd $PBS_ROOT_DIR
    ./torque-package-mom-linux-x86_64.sh --install
    ./torque-package-clients-linux-x86_64.sh --install
    /sbin/ldconfig
    
	if iscentos 7; then
		PBS_MOM_NODE=pbs_mom.service
		PBS_MOM_BOOT='systemctl enable '$PBS_MOM_NODE''
		RESTART_PBS_MOM='systemctl restart '$PBS_MOM_NODE''
	else
		PBS_MOM_NODE=pbs_mom
		PBS_MOM_BOOT='chkconfig --add '$PBS_MOM_NODE''
		RESTART_PBS_MOM='service '$PBS_MOM_NODE' restart'
	fi
    
    $PBS_MOM_BOOT
    $RESTART_PBS_MOM
}

Install_ubuntu_torque_master(){
	msg_info ""
	msg_info "Installing master node..."
    
    apt-get install -y torque-server torque-scheduler torque-client
    
    service torque-scheduler stop
    service torque-server stop
    
    #yes | pbs_server -t create
    service torque-server start
    
    echo $HOSTNAME > /etc/torque/server_name
    
	qmgr -c "set server scheduling=true"
    qmgr -c "set server acl_hosts = $HOSTNAME"
    qmgr -c "set server managers = root@$HOSTNAME"
    qmgr -c "set server operators = root@$HOSTNAME"
    qmgr -c "set server auto_node_np = True"
    
	qmgr -c "create queue jobq"
    qmgr -c "set queue jobq queue_type = Execution"
	qmgr -c "set queue jobq started=true"
	qmgr -c "set queue jobq enabled=true"
	qmgr -c "set queue jobq resources_default.nodes=4"
	qmgr -c "set queue jobq resources_default.walltime=3600"
	qmgr -c "set server default_queue=jobq"
	qmgr -c "set server keep_completed = 0"
	qmgr -c "set queue jobq resources_default.ncpus = 1"
	qmgr -c "set queue jobq resources_default.nodect = 1"
	qmgr -c "set queue jobq resources_default.nodes = 1"
	
	msg_info ""
	msg_info "Installing compute nodes..."
	if [ "$category" == "Deployment" ]; then
        compute_node=$(ss-get compute.enable)
        if [ "$compute_node" != "false" ]; then
	        install_exec_torque_ubuntu
        fi
        node_multiplicity=$(ss-get $SLAVE_NAME:multiplicity)
        if [ "$node_multiplicity" != "0" ]; then
        	for i in $(echo "$(ss-get $SLAVE_NAME:ids)" | sed 's/,/\n/g'); do
        	#for (( i=1; i <= $(ss-get $SLAVE_NAME:multiplicity); i++ )); do
        	
        	    if [ $IP_PARAMETER == "hostname" ]; then
                    node_host=$(ss-get $SLAVE_NAME.$i:ip.ready)
                else
                    node_host=$(ss-get $SLAVE_NAME.$i:$IP_PARAMETER)
                fi
        	    node_name=$SLAVE_NAME-$i
                
        		scp -prq -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null torque-package-mom-linux-x86_64.sh $node_host:$PBS_ROOT_DIR
        		scp -prq -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null torque-package-clients-linux-x86_64.sh $node_host:$PBS_ROOT_DIR
                
            	number_proc=$(ss-get $SLAVE_NAME.$i:cpu.nb)
            	qmgr -c 'create node '$node_name' np='$number_proc''
            done
        fi
    else
        install_exec_torque_ubuntu
    fi
    
    if [ $scheduler_type == "maui" ]; then
        cd $MAUI_ROOT_DIR
    	./configure --prefix=/opt/maui --with-pbs=/opt/torque --with-spooldir=/opt/maui/spool
    	make
    	make install
    else
        service torque-scheduler start
    fi
    
	#echo "export PATH=\$PATH:$PBS_ROOT_DIR/sbin:$PBS_ROOT_DIR/bin" > /etc/profile.d/torque.sh
	
    ss-set pbs.ready "true"
    msg_info "PBS is installed and configured."
}

Install_ubuntu_torque_slave(){
	msg_info ""
	msg_info "Installing slave node..."
    apt-get install -y torque-mom
    echo "$MASTER_HOSTNAME_SAFE" > /etc/torque/server_name
    service torque-mom restart
}

install_exec_torque_ubuntu(){
    apt-get install -y torque-mom
	number_proc=$(ss-get cpu.nb)
	qmgr -c 'create node '$HOSTNAME' np='$number_proc''
    service torque-mom restart
}

install_torque_master(){
    if iscentos; then
        install_centos_torque_master
    elif isubuntu; then
        Install_ubuntu_torque_master
    else
        ss-abort "centos or ubuntu only!!!"
    fi
}

install_torque_slave(){
    if iscentos; then
        install_centos_torque_slave
    elif isubuntu; then
        Install_ubuntu_torque_slave
    else
        ss-abort "centos or ubuntu only!!!"
    fi
}

UNSET_parameters_torque(){
    ss-set nfs.ready "false"
    ss-set pbs.ready "false"
}

add_nodes_torque(){
    if iscentos 7; then
    	INIT=/usr/lib/systemd/system
    	CONTRIB=$PBS_ROOT_DIR/contrib/systemd
    	TRQAUTHD=trqauthd.service
    	PBS_SERVER=pbs_server.service
        PBS_SCHED=pbs_sched.service
    elif iscentos 6; then
    	INIT=/etc/init.d
    	CONTRIB=$PBS_ROOT_DIR/contrib/init.d
    	TRQAUTHD=trqauthd
    	PBS_SERVER=pbs_server
        PBS_SCHED=pbs_sched
    fi
    
    ss-display "ADD slave..."
    for INSTANCE_NAME in $SLIPSTREAM_SCALING_VMS; do
        INSTANCE_NAME_SAFE=$(echo $INSTANCE_NAME | sed "s/\./-/g")
    
        echo "Processing $INSTANCE_NAME"
    
        if [ $IP_PARAMETER == "hostname" ]; then
            msg_info "Waiting ip of slave to be ready."
            ss-get --timeout=3600 $INSTANCE_NAME:ip.ready
            #NETWORK_MODE=$(ss-get $INSTANCE_NAME:network)
            #if [ "$NETWORK_MODE" == "Public" ]; then
            #    SLAVE_IP=$(ss-get $INSTANCE_NAME:$IP_PARAMETER)
            #else
            SLAVE_IP=$(ss-get $INSTANCE_NAME:ip.ready)
            #fi
        else
            SLAVE_IP=$(ss-get $INSTANCE_NAME:vpn.address)
        fi
        number_proc=$(ss-get $INSTANCE_NAME:cpu.nb)
        qmgr -c "create node $INSTANCE_NAME_SAFE np=$number_proc"
        
        NFS_export_add /home
       
       if grep -q $SLAVE_IP /etc/hosts; then
            echo "$SLAVE_IP ready"
        else
            echo "$SLAVE_IP $INSTANCE_NAME_SAFE" >> /etc/hosts
        fi        
    done
    
	if iscentos 7 ; then
		systemctl restart $PBS_SERVER
	elif iscentos 6; then
		service $PBS_SERVER restart
	fi
    
    NFS_start
    ss-set pbs.ready "true"
    ss-display "Slave is added."
}

rm_nodes_torque(){
    if iscentos 7; then
    	INIT=/usr/lib/systemd/system
    	CONTRIB=$PBS_ROOT_DIR/contrib/systemd
    	TRQAUTHD=trqauthd.service
    	PBS_SERVER=pbs_server.service
        PBS_SCHED=pbs_sched.service
    elif iscentos 6; then
    	INIT=/etc/init.d
    	CONTRIB=$PBS_ROOT_DIR/contrib/init.d
    	TRQAUTHD=trqauthd
    	PBS_SERVER=pbs_server
        PBS_SCHED=pbs_sched
    fi
    
    ss-display "RM slave..."
    for INSTANCE_NAME in $SLIPSTREAM_SCALING_VMS; do            
        INSTANCE_NAME_SAFE=$(echo $INSTANCE_NAME | sed "s/\./-/g")
        
        if [ $IP_PARAMETER == "hostname" ]; then
            msg_info "Waiting ip of slave to be ready."
            ss-get --timeout=3600 $INSTANCE_NAME:ip.ready
            #NETWORK_MODE=$(ss-get $INSTANCE_NAME:network)
            #if [ "$NETWORK_MODE" == "Public" ]; then
            #    SLAVE_IP=$(ss-get $INSTANCE_NAME:$IP_PARAMETER)
            #else
                SLAVE_IP=$(ss-get $INSTANCE_NAME:ip.ready)
                #fi
        else
            SLAVE_IP=$(ss-get $INSTANCE_NAME:vpn.address)
        fi
        qmgr -c "delete node $INSTANCE_NAME_SAFE"
        
        sed -i "s|$SLAVE_IP.*||g" /etc/hosts
        
        #remove nfs export
        sed -i 's|'$SLAVE_IP'(rw,sync,no_subtree_check,no_root_squash)||' /etc/exports
    done
    
	if iscentos 7 ; then
		systemctl restart $PBS_SERVER
	elif iscentos 6; then
		service $PBS_SERVER restart
	fi
    
    ss-display "Slave is removed."    
}


error(){ 
    echo "utilisez l'option -h pour en savoir plus" >&2 
} 

usage(){ 
    echo "Usage: source /scripts/cluster/torque/torque_install.sh" 
    echo "--help ou -h : afficher l'aide"
    echo "-m : Install pbs master" 
    echo "-s : Install pbs slave"
} 

master_help(){
    echo "You can do:"
} 

slave_help(){
    echo "You can do:"
} 

# Pas de paramètre 
[[ $# -lt 1 ]] && error

# -o : options courtes 
# -l : options longues 
options=$(getopt -o h,m,s: -l help -- "$@") 

set -- $options 

while true; do 
    case "$1" in 
        -m) master_help
            shift;;
        -s) slave_help
            shift;;
        -h|--help) usage 
            shift;;
        --)
            shift
            break;; 
        *) error 
            shift;;
    esac 
done