source /scripts/toolshed/os_detection.sh

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

create_tools_dir(){
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a directory in argument !"
    else 
        tools_dir=$1
    
        if [ ! -d "$tools_dir" ]; then
            mkdir -p $tools_dir
        fi
        echo "export PATH=\$PATH:$tools_dir" > /etc/profile.d/asm.sh
    fi
}

install_canu(){
    msg_info "Installing Canu..."
    
    tool_id="canu" 
    tool_bin="canu" 
    tool_version="1.5"
    tool_url="https://github.com/marbl/canu/archive"
    tool_ark="${tool_id}-${tool_version}"
    tool_pkg="v${tool_version}.tar.gz" 
    
    if iscentos 6; then
        wget http://people.centos.org/tru/devtools-2/devtools-2.repo -O /etc/yum.repos.d/devtools-2.repo
        # Installation des composantes nécessaires pour la compilation C++
        # (Version par defaut de gcc dans CentOS:4.4.7, alors que Canu requiert 4.5+)
        yum -y install devtoolset-2-gcc-c++
        yum -y install devtoolset-2-binutils
    else
        yum group install -y "Development Tools"
    fi

    # Fetch the tool pkg
    wget "${tool_url}/${tool_pkg}" 
    # install the tool 
    tar xzf ${tool_pkg}
    rm -rf ${tool_pkg}
    cd "${tool_ark}/src"
    if iscentos 6; then
        scl enable devtoolset-2 bash
    fi
    make
    
    cp -r ../Linux-amd64 $tools_dir/
    
    echo "export PATH=\$PATH:$tools_dir/Linux-amd64/bin" > /etc/profile.d/canu.sh
    
    msg_info "Canu is installed."
}

install_lordec(){
    msg_info "Installing Lordec..."
    
    tool_id="LoRDEC" 
    tool_bin="lordec" 
    tool_version="0.6"
    tool_url="http://www.atgc-montpellier.fr/download/sources/lordec" 
    tool_pkg="${tool_id}-${tool_version}"
    tool_ark="${tool_pkg}.tar.gz"

    dep_id="gatb-core"
    dep_version="1.1.0"
    
    if iscentos 6; then
        ## Ajout du repository de dev pour centOS
        wget http://people.centos.org/tru/devtools-2/devtools-2.repo -O /etc/yum.repos.d/devtools-2.repo
        # Installation des composantes nécessaires pour la compilation C++
        # (Version par defaut de gcc dans CentOS:4.4.7, alors que Lordec requiert 4.5+)
        yum -y install devtoolset-2-gcc-c++
        yum -y install devtoolset-2-binutils
    else
        yum group install -y "Development Tools"
    fi

    # Fetch and untar the tool package
    wget "${tool_url}/${tool_ark}" 
    tar xzf ${tool_ark}
    #rm -f ${tool_ark}
    cd "${tool_pkg}"
    # Modify gatb library version in Makefile
    sed -i "s/\(GATB_VER\)\=.*/\1\=${dep_version}/" Makefile
    sed -i "s/wget\ http\:\/\/gatb\-core\.gforge\.inria\.fr\/versions\/bin\/gatb\-core\-\$(GATB_VER)\-Linux\.tar\.gz/wget\ https\:\/\/github\.com\/GATB\/gatb\-core\/releases\/download\/v\$(GATB_VER)\/gatb\-core\-\$(GATB_VER)\-bin\-Linux\.tar\.gz/" Makefile
    sed -i "s/tar\ \-axf\ gatb\-core\-\$(GATB_VER)\-Linux\.tar\.gz/tar\ \-axf\ gatb\-core\-\$(GATB_VER)\-bin\-Linux\.tar\.gz/" Makefile
    # Fetch and install dependencies (gatb library)
    make install_dep
    #rm -f ${dep_id}-${dep_version}-Linux.tar.gz
    # Install tool via external shell running in the devtools environment
    if iscentos 6; then
        scl enable devtoolset-2 bash
    fi
    make
    

    mkdir -p $tools_dir/lordec/bin
    cp -r gatb-core-1.1.0-Linux/* $tools_dir/lordec
    cp lordec-* $tools_dir/lordec/bin
    cp test-lordec.sh $tools_dir/lordec
    cp -r DATA/ $tools_dir/lordec

    echo "export PATH=\$PATH:$tools_dir/lordec/bin" > /etc/profile.d/lordec.sh
    
    msg_info "Lordec is installed."
}

install_pipeline(){
    cp /scripts/biodatacloud/assemblage/lordec_2_fastq.pl $tools_dir
    cp /scripts/biodatacloud/assemblage/lordec_pipeline.pl $tools_dir
    chmod -R 755 $tools_dir/lordec_2_fastq.pl
    chmod -R 755 $tools_dir/lordec_pipeline.pl
}

create_readme(){
    # Pas de paramètre 
    if [[ $# -lt 1 ]]; then
        echo "This function expects a directory in argument !"
    else    
        README_DIR=$1
        
        if [ ! -d "$README_DIR" ]; then
            mkdir -p $README_DIR
        fi
        cp /scripts/biodatacloud/assemblage/HOWTO.README $README_DIR/HOWTO.README
        sed -i "s|<tools_dir>|$tools_dir|" $README_DIR/HOWTO.README
    fi
}