source /scripts/cluster/cluster_install.sh

install_elasticluster(){
    elastic_dir="/opt/elasticluster"
    playbook_dir=$elastic_dir/src/elasticluster/share/playbooks
    hosts_dir=$playbook_dir
    
    if isubuntu; then
        msg_info "Installing requirements with apt-get."
        apt-get update -y
        apt-get install -y gcc g++ git libc6-dev libffi-dev libssl-dev python python-dev git python3-pip
        curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
        python get-pip.py
    elif iscentos; then
        msg_info "Installing requirements with yum."
        yum update -y
        yum install -y gcc gcc-c++ git libffi-devel openssl-devel python python-devel git python-pip
    fi
    msg_info "Requirements are installed."
    
    msg_info "Installing package with pip."
    pip install pyOpenSSL ndg-httpsclient pyasn1  
    
    pip install --upgrade 'pip>=9.0.0'
    pip install --upgrade setuptools
    pip install backports.ssl_match_hostname
    #pip install requests[security]
    #pip install --upgrade ndg-httpsclient
    #pip install 'requests[security]' --upgrade
    
    mkdir $elastic_dir
    cd $elastic_dir
    git clone https://github.com/gc3-uzh-ch/elasticluster.git src
    cd src
    git checkout 6c8c8f8528d71e613cc17e71e1c6e3050b9f4b18
    
    pip install -e .
    elasticluster list-templates 1>/dev/null 2>/dev/null
    echo "" > $playbook_dir/hosts
    
    msg_info "Elasticluster is installed."
}

install_ansible(){
    msg_info "Installing ansible playbook."
    pip3 install ansible

    ansible_dir="/etc/ansible"
    mkdir -p $ansible_dir
    wget -O $ansible_dir/ansible.cfg https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg
    #sed -i '/\[defaults\]/a library = /usr/share/ansible:library' $ansible_dir/ansible.cfg
    sed -i 's|#host_key_checking.*|host_key_checking = False|' $ansible_dir/ansible.cfg
    sed -i 's|#pipelining.*|pipelining = True|' $ansible_dir/ansible.cfg
    
    msg_info "Ansible playbook is installed."
}

config_elasticluster(){
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a type of cluster in argument (slurm)!"
    else 
        cluster_type=$1
         
        check_if_vpn_or_not        
    
        #master
        MASTER_HOSTNAME=$(ss-get master.nodename)
        msg_info "Waiting ip of master to be ready."
        ss-get --timeout=3600 $MASTER_HOSTNAME:ip.ready
        MASTER_IP=$(ss-get $MASTER_HOSTNAME:ip.ready)
    
        ansible_user=root
        host_master=$MASTER_HOSTNAME-1
        NB_RAM_GO=$(ss-get $MASTER_HOSTNAME:ram.GB)
        memory_master=$(echo $(($NB_RAM_GO * 1000)))
        vcpu_master=$(ss-get $MASTER_HOSTNAME:cpu.nb)
        
        if [ $cluster_type == "slurm" ]; then
            msg_info "Configuring slurm hosts."
            #FIX controlmachine
            sed -i "s|ControlMachine=.*|ControlMachine="$host_master"|; s|PartitionName=main|PartitionName=normal|" $playbook_dir/roles/slurm-common/templates/slurm.conf.j2
    
            echo "[slurm_master]" > $playbook_dir/hosts
            echo "$host_master ansible_user=$ansible_user SLURM_ACCOUNTING_HOST=$host_master ansible_memtotal_mb=$memory_master ansible_processor_vcpus=$vcpu_master"  >> $playbook_dir/hosts
        fi
    
        #slave
        echo "" >> $playbook_dir/hosts
        
        if [ $cluster_type == "slurm" ]; then
            echo "[slurm_worker]" >> $playbook_dir/hosts
        fi
        
        SLAVE_NAME=$(ss-get slave.nodename)
        for (( i=1; i <= $(ss-get slave:multiplicity); i++ )); do
            msg_info "Waiting ip of slave to be ready."
            ss-get --timeout=3600 $SLAVE_NAME.$i:ip.ready
            SLAVE_IP=$(ss-get $SLAVE_NAME.$i:ip.ready)
            host_slave=$SLAVE_NAME-$i
            
            NB_RAM_GO=$(ss-get $SLAVE_NAME.$i:ram.GB)
            memory_slave=$(echo $(($NB_RAM_GO * 1000)))
            vcpu_slave=$(ss-get $SLAVE_NAME.$i:cpu.nb)
            
            if [ $cluster_type == "slurm" ]; then
                echo "$host_slave SLURM_ACCOUNTING_HOST=$host_slave ansible_memtotal_mb=$memory_slave ansible_processor_vcpus=$vcpu_slave" >> $playbook_dir/hosts
            fi
        done
        
        if [ $cluster_type == "slurm" ]; then
            echo "[slurm_submit]" >> $playbook_dir/hosts
            echo "$host_master"  >> $playbook_dir/hosts
            msg_info "Slurm hosts are configured."
        fi
    fi
}

fix_elasticluster(){
    #FIX bug with conditional
    sed -i "s|'is_ubuntu_trusty'|'is_ubuntu_trusty\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nis/tasks/init-Debian.yml
    sed -i "s|'is_debian_compatible'|'is_debian_compatible\|default([])'|g" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nis/tasks/main.yml
    sed -i "s|'is_rhel_compatible'|'is_rhel_compatible\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nis/tasks/main.yml
    sed -i "s|'is_debian_compatible'|'is_debian_compatible\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nfs-server/tasks/init-Debian.yml
    sed -i "s|'is_debian_jessie'|'is_debian_jessie\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/nfs-server/tasks/init-Debian.yml
    sed -i "s|is_debian_compatible|is_debian_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/init-Debian.yml
    sed -i "s|'is_rhel_compatible'|'is_rhel_compatible\|default([])'|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/main.yml
    sed -i "s|is_debian_compatible|is_debian_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/main.yml
    sed -i "s|is_rhel_compatible|is_rhel_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/main.yml
    sed -i "s|init_is_systemd|init_is_systemd\|default([])|g" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    sed -i "s|is_debian_compatible|is_debian_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    sed -i "s|is_rhel_compatible|is_rhel_compatible\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    sed -i "s|is_ubuntu_14_04|is_ubuntu_14_04\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    sed -i "s|is_ubuntu_14_10|is_ubuntu_14_10\|default([])|" /opt/elasticluster/src/elasticluster/share/playbooks/roles/slurm-common/tasks/munge.yml
    mkdir -p /etc/munge
    useradd munge
    chown munge /etc/munge
    apt-get install -y munge
    echo 'OPTIONS="--force"' >> /etc/default/munge
    chown munge /var/log/munge/
}

install_playbooks(){
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a type of cluster in argument (slurm)!"
    else
        cluster_type=$1
    
        if [ $cluster_type == "slurm" ]; then
            msg_info "Installing slurm cluster."
    
            #ansible_user=root
            #host_master=master-1
            #memory_master=$(ssh master 'echo $(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024)))')
            #vcpu_master=$(ssh master 'nproc')
            rm -f $playbook_dir/roles/slurm.yml
            wget -O $playbook_dir/roles/slurm.yml https://raw.githubusercontent.com/IFB-ElixirFr/biosphere-commons/master/scripts/cluster/slurm/slurm.yml

            ansible-playbook -M $playbook_dir/library -i $playbook_dir/hosts $playbook_dir/roles/slurm.yml
            #ansible-playbook -M $playbook_dir/library -i $playbook_dir/hosts --extra-vars "pkg_install_state='present' __at__='='" $playbook_dir/roles/slurm.yml

            #add new user
            sacctmgr -i add user $USER_NEW DefaultAccount=root AdminLevel=Admin

            slurmctld -D& 2> /opt/slurm_error_message.log
            ret=$?
            if [ $ret -ne 0 ]; then
                msg_info ""
                msg_info "Install Slurm aborted."
                msg_info ""
                ss-abort "$(cat /opt/slurm_error_message.log)"
            fi
            #ansible-playbook -M $playbook_dir/library -i $playbook_dir/hosts $playbook_dir/roles/slurm.yml --extra-vars "ansible_memtotal_mb=$ansible_memtotal_mb ansible_processor_vcpus=$ansible_processor_vcpus SLURM_ACCOUNTING_HOST=master-1 ansible_user=root"
            msg_info "Slurm cluster is installed."
        fi
    fi
}

add_nodes_elasticluster(){
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a type of cluster in argument (slurm)!"
    else 
        cluster_type=$1
        
        elastic_dir="/opt/elasticluster"
        playbook_dir=$elastic_dir/src/elasticluster/share/playbooks
        hosts_dir=$playbook_dir
        
        check_if_vpn_or_not
        
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
            
            NFS_export_add /home
       
           if grep -q $SLAVE_IP /etc/hosts; then
                echo "$SLAVE_IP ready"
            else
                echo "$SLAVE_IP $INSTANCE_NAME_SAFE" >> /etc/hosts
            fi
            
            host_slave=$INSTANCE_NAME_SAFE
            
            NB_RAM_GO=$(ss-get $INSTANCE_NAME:ram.GB)
            memory_slave=$(echo $(($NB_RAM_GO * 1000)))
            vcpu_slave=$(ss-get $INSTANCE_NAME:cpu.nb)
        
            if [ $cluster_type == "slurm" ]; then
                sed -i '/\[slurm_worker\]/a '$host_slave' SLURM_ACCOUNTING_HOST='$host_slave' ansible_memtotal_mb='$memory_slave' ansible_processor_vcpus='$vcpu_slave'' $playbook_dir/hosts
            fi
            
            status=$(ssh -q -o "BatchMode=yes" $INSTANCE_NAME_SAFE "echo 2>&1" && echo "OK" || echo "NOK")
            msg_info "Waiting SSH to be configured."
        	while [ "$status" == "NOK" ]
        	do
        		sleep 10;
        		status=$(ssh -q -o "BatchMode=yes" $INSTANCE_NAME_SAFE "echo 2>&1" && echo "OK" || echo "NOK")
        	done
        done
        
        if [ $cluster_type == "slurm" ]; then
            msg_info "Installing slurm cluster."
            ansible-playbook -M $playbook_dir/library -i $playbook_dir/hosts $playbook_dir/roles/slurm.yml
            
            #add new user
            sacctmgr -i add user $USER_NEW DefaultAccount=root AdminLevel=Admin
            
            slurmctld -D&
            msg_info "Slurm cluster is installed."            
        fi
        NFS_start
    fi
}

rm_nodes_elasticluster(){
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a type of cluster in argument (slurm)!"
    else 
        cluster_type=$1
        
        elastic_dir="/opt/elasticluster"
        playbook_dir=$elastic_dir/src/elasticluster/share/playbooks
        hosts_dir=$playbook_dir
        
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
        
            host_slave=$INSTANCE_NAME_SAFE
        
            if [ $cluster_type == "slurm" ]; then
                sed -i '/'$host_slave'/d' $playbook_dir/hosts
            fi
            
            sed -i "s|$SLAVE_IP.*||g" /etc/hosts
        
            #remove nfs export
            sed -i 's|'$SLAVE_IP'(rw,sync,no_subtree_check,no_root_squash)||' /etc/exports
        done
        
        if [ $cluster_type == "slurm" ]; then
            msg_info "Installing slurm cluster."
            ansible-playbook -M $playbook_dir/library -i $playbook_dir/hosts $playbook_dir/roles/slurm.yml
            
            #add new user
            sacctmgr -i add user $USER_NEW DefaultAccount=root AdminLevel=Admin
            
            slurmctld -D&
            msg_info "Slurm cluster is installed."
        fi
    fi
}
