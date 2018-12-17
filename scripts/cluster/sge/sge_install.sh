source /scripts/cluster/cluster_install.sh

initiate_master()
{
    check_if_vpn_or_not

    user_add

    ID=1
    SGE_ROOT_DIR=/tmp/sge
    mkdir -p $SGE_ROOT_DIR
    
    HOSTIP=$(ss-get $IP_PARAMETER)

    if [ "$category" == "Deployment" ]; then
        ss-set master.nodename $(ss-get nodename)
        HOSTNAME=$(ss-get nodename)-$ID

        ss-get --timeout=3600 slave.nodename
        SLAVE_NAME=$(ss-get slave.nodename)
        #echo $HOSTIP $HOSTNAME |  tee -a /etc/hosts
    else
        HOSTNAME=machine-$ID
        echo $HOSTIP $HOSTNAME |  tee -a /etc/hosts
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
    
    if isubuntu; then
        if grep -q "myhostname = ." "/etc/postfix/main.cf"; then
            sed -i "s|myhostname = .*|myhostname = $HOSTNAME|" /etc/postfix/main.cf
            /etc/init.d/postfix start
            /etc/init.d/postfix reload
        fi
    fi    
}

initiate_slave()
{
    check_if_vpn_or_not

    user_add
    
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
    hostname $SLAVE_HOSTNAME_SAFE
    
    if isubuntu; then
        if grep -q "myhostname = ." "/etc/postfix/main.cf"; then
            sed -i "s|myhostname = .*|myhostname = $SLAVE_HOSTNAME_SAFE|" /etc/postfix/main.cf
            /etc/init.d/postfix reload
        fi
    fi
}

message_at_boot_master_sge()
{
    echo "" > /etc/motd
    echo "$USER_NEW created for launch job" >> /etc/motd
    echo "" >> /etc/motd
    echo "qhost : show the status of Sun Grid Engine hosts, queues, jobs" >> /etc/motd
    echo "qstat -f : show the status of Sun Grid Engine jobs and queues" >> /etc/motd
    echo "" >> /etc/motd
}

message_at_boot_slave()
{
    echo "" > /etc/motd
    echo "$USER_NEW created for launch job" >> /etc/motd
    echo "" >> /etc/motd
}

#####
# Install SGE
#####

check_if_sge_is_ready_on_master(){
    ss-get --timeout=3600 $MASTER_HOSTNAME:sge.ready
    sge_ready=$(ss-get $MASTER_HOSTNAME:sge.ready)
    msg_info "Waiting SGE to be ready."
	while [ "$sge_ready" == "false" ]
	do
		sleep 10;
		sge_ready=$(ss-get $MASTER_HOSTNAME:sge.ready)
	done
}

Install_SGE_master()
{
    msg_info "Installing SGE..."
    
    if iscentos; then
        SGEDIR=/opt/sge
        mkdir -p $SGEDIR
        chmod 775 $SGEDIR
        
        sge_version="8.1.9"
        yum remove -y gridengine*
        yum install -y https://arc.liv.ac.uk/downloads/SGE/releases/$sge_version/gridengine-$sge_version-1.el6.x86_64.rpm
        yum install -y https://arc.liv.ac.uk/downloads/SGE/releases/$sge_version/gridengine-qmaster-$sge_version-1.el6.x86_64.rpm
        yum install -y https://arc.liv.ac.uk/downloads/SGE/releases/$sge_version/gridengine-qmon-$sge_version-1.el6.x86_64.rpm
        yum install -y https://arc.liv.ac.uk/downloads/SGE/releases/$sge_version/gridengine-guiinst-$sge_version-1.el6.noarch.rpm
        yum install -y https://arc.liv.ac.uk/downloads/SGE/releases/$sge_version/gridengine-execd-$sge_version-1.el6.x86_64.rpm
        #yum install -y https://arc.liv.ac.uk/downloads/SGE/releases/$sge_version/gridengine-debuginfo-$sge_version-1.el6.x86_64.rpm
        
        #wget -O /opt/sge/util/install_modules/inst_ifb.conf https://github.com/cyclone-project/usecases-hackathon-2016/raw/master/scripts/cluster/sge/inst_ifb.conf
        
    	cd /opt/sge
    	./inst_sge -m -auto util/install_modules/inst_template.conf
    	. /opt/sge/default/common/settings.sh
        wget -O /etc/profile.d/sge_lib.sh https://github.com/cyclone-project/usecases-hackathon-2016/raw/master/scripts/cluster/sge/sge_lib.sh
        msg_info "SGE is installed."
        message_at_boot_master_sge        
    elif isubuntu; then
        # Configure the master hostname for Grid Engine
        echo "gridengine-master       shared/gridenginemaster string  $HOSTNAME" |  debconf-set-selections
        echo "gridengine-master       shared/gridenginecell   string  default" |  debconf-set-selections
        echo "gridengine-master       shared/gridengineconfig boolean false" |  debconf-set-selections
        echo "gridengine-common       shared/gridenginemaster string  $HOSTNAME" |  debconf-set-selections
        echo "gridengine-common       shared/gridenginecell   string  default" |  debconf-set-selections
        echo "gridengine-common       shared/gridengineconfig boolean false" |  debconf-set-selections
        echo "gridengine-client       shared/gridenginemaster string  $HOSTNAME" |  debconf-set-selections
        echo "gridengine-client       shared/gridenginecell   string  default" |  debconf-set-selections
        echo "gridengine-client       shared/gridengineconfig boolean false" |  debconf-set-selections
        # Postfix mail server is also installed as a dependency
        echo "postfix postfix/main_mailer_type        select  No configuration" |  debconf-set-selections
    
        # Install Grid Engine
        DEBIAN_FRONTEND=noninteractive apt-get install -y gridengine-master gridengine-client
    
        # Set up Grid Engine
        su - sgeadmin -s/bin/bash -c '/usr/share/gridengine/scripts/init_cluster /var/lib/gridengine default /var/spool/gridengine/spooldb sgeadmin'

        service gridengine-master restart 2> /opt/sge_error_message.log
        ret=$?
        if [ $ret -ne 0 ]; then
        	msg_info ""
        	msg_info "Install SGE aborted."
            msg_info ""
            ss-abort "$(cat /opt/sge_error_message.log)"
        fi
    
        # Disable Postfix
        service postfix stop
        update-rc.d postfix disable
    
        msg_info "SGE is installed."
        message_at_boot_master_sge
        
    else
        echo "Unsupported osfamily"
    fi
    
}

Install_SGE_slave()
{
    msg_info "Installing and Configuring SGE..."
    
    if iscentos; then
        SGEDIR=/opt/sge
        mkdir -p $SGEDIR
        chmod 775 $SGEDIR
        
        sge_version="8.1.9"
        yum install -y https://arc.liv.ac.uk/downloads/SGE/releases/$sge_version/gridengine-$sge_version-1.el6.x86_64.rpm
        cd /opt/sge
        . /opt/sge/default/common/settings.sh         
        ./inst_sge -x -auto util/install_modules/inst_template.conf
        wget -O /etc/profile.d/sge_lib.sh https://github.com/cyclone-project/usecases-hackathon-2016/raw/master/scripts/cluster/sge/sge_lib.sh
    elif isubuntu; then   
        echo "gridengine-common       shared/gridenginemaster string  $MASTER_HOSTNAME_SAFE" |  debconf-set-selections
        echo "gridengine-common       shared/gridenginecell   string  default" |  debconf-set-selections
        echo "gridengine-common       shared/gridengineconfig boolean false" |  debconf-set-selections
        echo "gridengine-client       shared/gridenginemaster string  $MASTER_HOSTNAME_SAFE" |  debconf-set-selections
        echo "gridengine-client       shared/gridenginecell   string  default" |  debconf-set-selections
        echo "gridengine-client       shared/gridengineconfig boolean false" |  debconf-set-selections
        echo "postfix postfix/main_mailer_type        select  No configuration" |  debconf-set-selections
    
        DEBIAN_FRONTEND=noninteractive apt-get install -y gridengine-exec gridengine-client
    
        service postfix stop
        update-rc.d postfix disable
    
        echo $MASTER_HOSTNAME_SAFE |  tee /var/lib/gridengine/default/common/act_qmaster
        service gridengine-exec restart 2> /opt/sge_error_message.log
        ret=$?
        if [ $ret -ne 0 ]; then
        	msg_info ""
        	msg_info "Install SGE aborted."
            msg_info ""
            ss-abort "$(cat /opt/sge_error_message.log)"
        fi
    
        msg_info "SGE is installed and configured."
        message_at_boot_slave
    else
        echo "Unsupported osfamily"
    fi
}

Install_EXEC()
{
    QUEUE=all.q
    SLOTS='nproc'
    
    # add to the execution host list
    TMPFILE=/tmp/sge.hostname-$HOSTNAME
    echo -e "hostname $HOSTNAME\nload_scaling NONE\ncomplex_values NONE\nuser_lists NONE\nxuser_lists NONE\nprojects NONE\nxprojects NONE\nusage_scaling NONE\nreport_variables NONE" > $TMPFILE
    qconf -Ae $TMPFILE
    rm $TMPFILE
    
    # add to the all hosts list
    qconf -aattr hostgroup hostlist $HOSTNAME @allhosts
    
    # enable the host for the queue, in case it was disabled and not removed
    qmod -e $QUEUE@$HOSTNAME
    
    if [ "$SLOTS" ]; then
        qconf -aattr queue slots "[$HOSTNAME=$SLOTS]" $QUEUE
    fi
    
    if iscentos; then
        cd /opt/sge
        . /opt/sge/default/common/settings.sh        
        ./inst_sge -x -auto util/install_modules/inst_template.conf
    elif isubuntu; then
        echo "gridengine-common       shared/gridenginemaster string  $HOSTNAME" |  debconf-set-selections
        echo "gridengine-common       shared/gridenginecell   string  default" |  debconf-set-selections
        echo "gridengine-common       shared/gridengineconfig boolean false" |  debconf-set-selections
        echo "gridengine-client       shared/gridenginemaster string  $HOSTNAME" |  debconf-set-selections
        echo "gridengine-client       shared/gridenginecell   string  default" |  debconf-set-selections
        echo "gridengine-client       shared/gridengineconfig boolean false" |  debconf-set-selections
        echo "postfix postfix/main_mailer_type        select  No configuration" |  debconf-set-selections
    
        DEBIAN_FRONTEND=noninteractive apt-get install -y gridengine-exec gridengine-client
    
        service postfix stop
        update-rc.d postfix disable
    
        echo $HOSTNAME |  tee /var/lib/gridengine/default/common/act_qmaster
        service gridengine-exec restart 2> /opt/sge_error_message.log
        ret=$?
        if [ $ret -ne 0 ]; then
        	msg_info ""
        	msg_info "Install SGE aborted."
            msg_info ""
            ss-abort "$(cat /opt/sge_error_message.log)"
        fi
    else
        echo "Unsupported osfamily"
    fi
}
 
Config_SGE_master()
{   
    msg_info "Configuring SGE..."
    
    qconf -am $USER_NEW
	qconf -ao $USER_NEW
	
    # change scheduler config
    
    echo "algorithm                         default"  > $SGE_ROOT_DIR/grid
    echo "schedule_interval                 0:0:1" >> $SGE_ROOT_DIR/grid
    echo "maxujobs                          0" >> $SGE_ROOT_DIR/grid
    echo "queue_sort_method                 load" >> $SGE_ROOT_DIR/grid
    echo "job_load_adjustments              np_load_avg=0.50" >> $SGE_ROOT_DIR/grid
    echo "load_adjustment_decay_time        0:7:30" >> $SGE_ROOT_DIR/grid
    echo "load_formula                      np_load_avg" >> $SGE_ROOT_DIR/grid
    echo "schedd_job_info                   true" >> $SGE_ROOT_DIR/grid
    echo "flush_submit_sec                  0" >> $SGE_ROOT_DIR/grid
    echo "flush_finish_sec                  0" >> $SGE_ROOT_DIR/grid
    echo "params                            none" >> $SGE_ROOT_DIR/grid
    echo "reprioritize_interval             0:0:0" >> $SGE_ROOT_DIR/grid
    echo "halftime                          168" >> $SGE_ROOT_DIR/grid
    echo "usage_weight_list                 cpu=1.000000,mem=0.000000,io=0.000000" >> $SGE_ROOT_DIR/grid
    echo "compensation_factor               5.000000" >> $SGE_ROOT_DIR/grid
    echo "weight_user                       0.250000" >> $SGE_ROOT_DIR/grid
    echo "weight_project                    0.250000" >> $SGE_ROOT_DIR/grid
    echo "weight_department                 0.250000" >> $SGE_ROOT_DIR/grid
    echo "weight_job                        0.250000" >> $SGE_ROOT_DIR/grid
    echo "weight_tickets_functional         0" >> $SGE_ROOT_DIR/grid
    echo "weight_tickets_share              0" >> $SGE_ROOT_DIR/grid
    echo "share_override_tickets            TRUE" >> $SGE_ROOT_DIR/grid
    echo "share_functional_shares           TRUE" >> $SGE_ROOT_DIR/grid
    echo "max_functional_jobs_to_schedule   200" >> $SGE_ROOT_DIR/grid
    echo "report_pjob_tickets               TRUE" >> $SGE_ROOT_DIR/grid
    echo "max_pending_tasks_per_job         50" >> $SGE_ROOT_DIR/grid
    echo "halflife_decay_list               none" >> $SGE_ROOT_DIR/grid
    echo "policy_hierarchy                  OFS" >> $SGE_ROOT_DIR/grid
    echo "weight_ticket                     0.500000" >> $SGE_ROOT_DIR/grid
    echo "weight_waiting_time               0.278000" >> $SGE_ROOT_DIR/grid
    echo "weight_deadline                   3600000.000000" >> $SGE_ROOT_DIR/grid
    echo "weight_urgency                    0.500000" >> $SGE_ROOT_DIR/grid
    echo "weight_priority                   0.000000" >> $SGE_ROOT_DIR/grid
    echo "max_reservation                   0" >> $SGE_ROOT_DIR/grid
    echo "default_duration                  INFINITY" >> $SGE_ROOT_DIR/grid
    qconf -Msconf $SGE_ROOT_DIR/grid
    rm $SGE_ROOT_DIR/grid
    
    wget -O $SGE_ROOT_DIR/complex.conf https://github.com/cyclone-project/usecases-hackathon-2016/raw/master/scripts/cluster/sge/complex.conf
	qconf -Mc $SGE_ROOT_DIR/complex.conf
    
    # create a host list
    echo -e "group_name @allhosts\nhostlist NONE" > $SGE_ROOT_DIR/grid
    qconf -Ahgrp $SGE_ROOT_DIR/grid
    rm $SGE_ROOT_DIR/grid
    
    # create a queue
    echo "qname                 all.q" > $SGE_ROOT_DIR/grid
    echo "hostlist              @allhosts" >> $SGE_ROOT_DIR/grid
    echo "seq_no                0" >> $SGE_ROOT_DIR/grid
    echo "load_thresholds       NONE" >> $SGE_ROOT_DIR/grid
    echo "suspend_thresholds    NONE" >> $SGE_ROOT_DIR/grid
    echo "nsuspend              1" >> $SGE_ROOT_DIR/grid
    echo "suspend_interval      00:00:01" >> $SGE_ROOT_DIR/grid
    echo "priority              0" >> $SGE_ROOT_DIR/grid
    echo "min_cpu_interval      00:00:01" >> $SGE_ROOT_DIR/grid
    echo "processors            UNDEFINED" >> $SGE_ROOT_DIR/grid
    echo "qtype                 BATCH INTERACTIVE" >> $SGE_ROOT_DIR/grid
    echo "ckpt_list             NONE" >> $SGE_ROOT_DIR/grid
    echo "pe_list               make" >> $SGE_ROOT_DIR/grid
    echo "rerun                 FALSE" >> $SGE_ROOT_DIR/grid
    echo "slots                 2" >> $SGE_ROOT_DIR/grid
    echo "tmpdir                /tmp" >> $SGE_ROOT_DIR/grid
    echo "shell                 /bin/csh" >> $SGE_ROOT_DIR/grid
    echo "prolog                NONE" >> $SGE_ROOT_DIR/grid
    echo "epilog                NONE" >> $SGE_ROOT_DIR/grid
    echo "shell_start_mode      posix_compliant" >> $SGE_ROOT_DIR/grid
    echo "starter_method        NONE" >> $SGE_ROOT_DIR/grid
    echo "suspend_method        NONE" >> $SGE_ROOT_DIR/grid
    echo "resume_method         NONE" >> $SGE_ROOT_DIR/grid
    echo "terminate_method      NONE" >> $SGE_ROOT_DIR/grid
    echo "notify                00:00:01" >> $SGE_ROOT_DIR/grid
    echo "owner_list            NONE" >> $SGE_ROOT_DIR/grid
    echo "user_lists            NONE" >> $SGE_ROOT_DIR/grid
    echo "xuser_lists           NONE" >> $SGE_ROOT_DIR/grid
    echo "subordinate_list      NONE" >> $SGE_ROOT_DIR/grid
    echo "complex_values        NONE" >> $SGE_ROOT_DIR/grid
    echo "projects              NONE" >> $SGE_ROOT_DIR/grid
    echo "xprojects             NONE" >> $SGE_ROOT_DIR/grid
    echo "calendar              NONE" >> $SGE_ROOT_DIR/grid
    echo "initial_state         default" >> $SGE_ROOT_DIR/grid
    echo "s_rt                  INFINITY" >> $SGE_ROOT_DIR/grid
    echo "h_rt                  INFINITY" >> $SGE_ROOT_DIR/grid
    echo "s_cpu                 INFINITY" >> $SGE_ROOT_DIR/grid
    echo "h_cpu                 INFINITY" >> $SGE_ROOT_DIR/grid
    echo "s_fsize               INFINITY" >> $SGE_ROOT_DIR/grid
    echo "h_fsize               INFINITY" >> $SGE_ROOT_DIR/grid
    echo "s_data                INFINITY" >> $SGE_ROOT_DIR/grid
    echo "h_data                INFINITY" >> $SGE_ROOT_DIR/grid
    echo "s_stack               INFINITY" >> $SGE_ROOT_DIR/grid
    echo "h_stack               INFINITY" >> $SGE_ROOT_DIR/grid
    echo "s_core                INFINITY" >> $SGE_ROOT_DIR/grid
    echo "h_core                INFINITY" >> $SGE_ROOT_DIR/grid
    echo "s_rss                 INFINITY" >> $SGE_ROOT_DIR/grid
    echo "h_rss                 INFINITY" >> $SGE_ROOT_DIR/grid
    echo "s_vmem                INFINITY" >> $SGE_ROOT_DIR/grid
    echo "h_vmem                INFINITY" >> $SGE_ROOT_DIR/grid
    qconf -Aq $SGE_ROOT_DIR/grid
    rm $SGE_ROOT_DIR/grid
    
    # add the current host to the submit host list (will be able to do qsub)
    qconf -as $HOSTNAME
	
	# add to the admin host list so that we can do qstat, etc.
    qconf -ah $HOSTNAME
	
	# add slaves
	if [ "$category" == "Deployment" ]; then
        compute_node=$(ss-get compute.enable)
        if [ "$compute_node" != "false" ]; then
	        Install_EXEC
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
        	    node_name=$(echo $node_name | sed "s|_|-|g")
        	    #echo $node_host $node_name |  tee -a /etc/hosts
        	    
                msg_info "\t. on node $node_host"
        		
        		QUEUE=all.q
                #SLOTS=$(ssh root@$node_host 'nproc')
                SLOTS=$(ss-get $SLAVE_NAME.$i:cpu.nb)
                
                # add to the execution host list
                TMPFILE=/tmp/sge.hostname-$node_name
                echo -e "hostname $node_name\nload_scaling NONE\ncomplex_values NONE\nuser_lists NONE\nxuser_lists NONE\nprojects NONE\nxprojects NONE\nusage_scaling NONE\nreport_variables NONE" > $TMPFILE
                qconf -Ae $TMPFILE
                rm $TMPFILE
                
                # add to the all hosts list
                qconf -aattr hostgroup hostlist $node_name @allhosts
                
                # enable the host for the queue, in case it was disabled and not removed
                qmod -e $QUEUE@$node_name
                
                if [ "$SLOTS" ]; then
                    qconf -aattr queue slots "[$node_name=$SLOTS]" $QUEUE
                fi
                qconf -ah $node_name
            done
        fi
    else
        Install_EXEC
	fi
	ss-set sge.ready "true"
	
	msg_info "SGE is configured."
}

add_nodes() {
    MASTER_ID=1
    category=$(ss-get ss:category)
    if [ "$category" == "Deployment" ]; then
        HOSTNAME=$(ss-get nodename)-$MASTER_ID
    else
        HOSTNAME=machine-$MASTER_ID
    fi
    HOSTNAME=$(echo $HOSTNAME | sed "s|_|-|g")
    echo "$HOSTNAME" > /etc/hostname
    hostname $HOSTNAME
    
    ss-display "ADD slave..."
    for INSTANCE_NAME in $SLIPSTREAM_SCALING_VMS; do
        INSTANCE_NAME_SAFE=$(echo $INSTANCE_NAME | sed "s/\./-/g")
        
        echo "Processing $INSTANCE_NAME"
        # Do something here. Example:
        #ss-get $INSTANCE_NAME:ready
        
        if [ $IP_PARAMETER == "hostname" ]; then
            ss-get --timeout=3600 $INSTANCE_NAME:net.services.enable
            ss-set $INSTANCE_NAME:net.services.enable "[]"
            ss-get --timeout=3600 $INSTANCE_NAME:ip.ready
            PUBLIC_SLAVE_IP=$(ss-get $INSTANCE_NAME:$IP_PARAMETER)
            SLAVE_IP=$(ss-get $INSTANCE_NAME:ip.ready)
        else
            PUBLIC_SLAVE_IP=$(ss-get $INSTANCE_NAME:hostname)
            SLAVE_IP=$(ss-get $INSTANCE_NAME:$IP_PARAMETER)
        fi
        sed -i "s|$PUBLIC_SLAVE_IP|$SLAVE_IP|g" /etc/hosts
        echo "New instance of $SLIPSTREAM_SCALING_NODE: $INSTANCE_NAME_SAFE, $SLAVE_IP"
        
        NFS_export_add /root/mydisk
        NFS_export_add /home/$USER_NEW
        if iscentos; then
            NFS_export_add /opt/sge
        fi
       
       if grep -q $SLAVE_IP /etc/hosts; then
            echo "$SLAVE_IP ready"
        else
            echo "$SLAVE_IP $INSTANCE_NAME_SAFE" >> /etc/hosts
        fi
        
        QUEUE=all.q
        #SLOTS=$(ssh root@$SLAVE_IP 'nproc')
        SLOTS=$(ss-get $INSTANCE_NAME:cpu.nb)
        
        # add to the execution host list
        TMPFILE=/tmp/sge.hostname-$SLAVE_IP
        echo -e "hostname $INSTANCE_NAME_SAFE\nload_scaling NONE\ncomplex_values NONE\nuser_lists NONE\nxuser_lists NONE\nprojects NONE\nxprojects NONE\nusage_scaling NONE\nreport_variables NONE" > $TMPFILE
        qconf -Ae $TMPFILE
        rm $TMPFILE
        
        # add to the all hosts list
        qconf -aattr hostgroup hostlist $INSTANCE_NAME_SAFE @allhosts
        
        # enable the host for the queue, in case it was disabled and not removed
        qmod -e $QUEUE@$INSTANCE_NAME_SAFE
        
        if [ "$SLOTS" ]; then
            qconf -aattr queue slots "[$INSTANCE_NAME_SAFE=$SLOTS]" $QUEUE
        fi
        qconf -ah $INSTANCE_NAME_SAFE
    done
    NFS_start
    ss-set sge.ready "true"
    ss-display "Slave is added."
}

## Remove slaves
rm_nodes() {
    MASTER_ID=1
    category=$(ss-get ss:category)
    if [ "$category" == "Deployment" ]; then
        HOSTNAME=$(ss-get nodename)-$MASTER_ID
    else
        HOSTNAME=machine-$MASTER_ID
    fi
    HOSTNAME=$(echo $HOSTNAME | sed "s|_|-|g")
    echo "$HOSTNAME" > /etc/hostname
    hostname $HOSTNAME
    
    ss-display "RM slave..."
    for INSTANCE_NAME in $SLIPSTREAM_SCALING_VMS; do
        INSTANCE_NAME_SAFE=$(echo $INSTANCE_NAME | sed "s/\./-/g")
    
        echo "Processing $INSTANCE_NAME"
        # Do something here. Example:
        #ss-get $INSTANCE_NAME:ready
        #SLAVE_IP=$(ss-get $INSTANCE_NAME:$IP_PARAMETER)
        
        if [ $IP_PARAMETER == "hostname" ]; then
            ss-get --timeout=3600 $INSTANCE_NAME:ip.ready
            PUBLIC_SLAVE_IP=$(ss-get $INSTANCE_NAME:$IP_PARAMETER)
            SLAVE_IP=$(ss-get $INSTANCE_NAME:ip.ready)
        else
            PUBLIC_SLAVE_IP=$(ss-get $INSTANCE_NAME:hostname)
            SLAVE_IP=$(ss-get $INSTANCE_NAME:$IP_PARAMETER)
        fi
        sed -i "s|$SLAVE_IP.*||g" /etc/hosts
        
        #echo "$SLAVE_IP $INSTANCE_NAME_SAFE" >> /etc/hosts
        
        QUEUE=all.q
        
        # disable the host to avoid any jobs to be allocated to this host
        qmod -d $QUEUE@$INSTANCE_NAME_SAFE
        
        # remove it from the all hosts list
        qconf -dattr hostgroup hostlist $INSTANCE_NAME_SAFE @allhosts
        
        # remove it from the execution host list
        qconf -de $INSTANCE_NAME_SAFE
        
        # reschedules all jobs currently running in this  queue
        qmod -f -rq $QUEUE@$INSTANCE_NAME_SAFE
        
        # delete specific slot count for the host
        #qconf -purge queue slots $QUEUE@$SLAVE_IP
        
        #remove nfs export
        sed -i 's|'$SLAVE_IP'(rw,sync,no_subtree_check,no_root_squash)||' /etc/exports
    done
    ss-display "Slave is removed."
}


error(){ 
    echo "utilisez l'option -h pour en savoir plus" >&2 
} 

usage(){ 
    echo "Usage: source /scripts/cluster/sge/sge_install.sh" 
    echo "--help ou -h : afficher l'aide"
    echo "-m : Install sge master" 
    echo "-s : Install sge slave"
    echo "-a : add nodes"
    echo "-r : remove nodes"
} 

master_help(){
    echo "You can do:"
    echo "    #Post-install part:"
    echo "    make_file_test_sge /root/mydisk"
    echo "    check_if_vpn_or_not"
    echo "    if [ \$IP_PARAMETER == 'hostname' ]; then"
    echo "        if isubuntu 14; then"
    echo "            initiate_install_edugain"
    echo "        elif isubuntu 16; then"
    echo "            initiate_install_edugain_ubuntu16"
    echo "        fi"
    echo "    fi"
    echo "    "
    echo "    #Deployment part:"
    echo "    check_if_vpn_or_not"
    echo "    user_add"
    echo "    initiate_master"
    echo "    if [ \$IP_PARAMETER == 'hostname' ]; then"
    echo "        if $(isubuntu 14) || $(isubuntu 16); then"
    echo "            install_edugain"
    echo "        fi"
    echo "        check_ip"
    echo "        if [ '\$category' == 'Deployment' ]; then"
    echo "            check_ip_slave_for_master"
    echo "        fi"
    echo "    fi"
    echo "    if [ '\$category' == 'Deployment' ]; then"
    echo "        node_multiplicity=$(ss-get \$SLAVE_NAME:multiplicity)"
    echo "        if [ '\$node_multiplicity '!= '0' ]; then"
    echo "            NFS_export /root/mydisk"
    echo "            NFS_export /home/\$USER_NEW"
    echo "            if iscentos; then"
    echo "                NFS_export /opt/sge"
    echo "            fi"
    echo "            NFS_start"
    echo "        fi"
    echo "    fi"
    echo "    Install_SGE_master"
    echo "    Config_SGE_master"
}

add_nodes_help(){
    echo "You can do:"
    echo "    check_if_vpn_or_not"
    echo "    UNSET_parameters"
    echo "    if [ '\$SLIPSTREAM_SCALING_NODE' == 'slave' ]; then"
    echo "        add_nodes"
    echo "    else"
    echo "        ss-abort 'Only slave can be added'"
    echo "    fi"
}

rm_nodes_help(){
    echo "You can do:"
    echo "    check_if_vpn_or_not"
    echo "    if [ '\$SLIPSTREAM_SCALING_NODE' == 'slave' ]; then"
    echo "        rm_nodes"
    echo "    else"
    echo "        ss-abort 'Only slave can be removed'"
    echo "    fi"
}

slave_help(){
    echo "You can do:"
    echo "    #Post-install part:"
    echo "    check_if_vpn_or_not"
    echo "    "
    echo "    #Deployment part:"
    echo "    check_if_vpn_or_not"
    echo "    user_add"
    echo "    initiate_slave"
    echo "    if [ \$IP_PARAMETER == 'hostname' ]; then"
    echo "        check_ip"
    echo "        if [ '\$category '== 'Deployment' ]; then"
    echo "            check_ip_master_for_slave"
    echo "        fi"
    echo "    fi"
    echo "    NFS_ready"
    echo "    NFS_mount /root/mydisk"
    echo "    NFS_mount /home/\$USER_NEW"
    echo "    if iscentos; then"
    echo "        mkdir -p /opt/sge"
    echo "        NFS_mount /opt/sge"
    echo "    fi"
    echo "    check_if_sge_is_ready_on_master"
    echo "    Install_SGE_slave"
} 

# Pas de paramètre 
[[ $# -lt 1 ]] && error

# -o : options courtes 
# -l : options longues 
options=$(getopt -o h,m,s,a,r: -l help -- "$@") 

set -- $options 

while true; do 
    case "$1" in 
        -m) master_help
            shift;;
        -s) slave_help
            shift;;
        -a) add_nodes_help
            shift;;
        -r) rm_nodes_help
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