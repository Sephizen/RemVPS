#!/bin/bash

# Clear screen
clear

# ==========================================
# Colors (using tput for better compatibility)
# ==========================================
if [ -t 1 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    PURPLE=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED="" GREEN="" YELLOW="" BLUE="" PURPLE="" CYAN="" WHITE="" BOLD="" NC=""
fi

# Typing effect
type_effect() {
    local text="$1"
    local delay="${2:-0.01}"
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
    echo
}

# Loading bar
loading_bar() {
    local title="$1"
    printf "${YELLOW}⏳ %s ${NC}[          ]" "$title"
    sleep 0.25
    printf "\r${YELLOW}⏳ %s ${NC}[===       ]" "$title"
    sleep 0.25
    printf "\r${YELLOW}⏳ %s ${NC}[======    ]" "$title"
    sleep 0.25
    printf "\r${YELLOW}⏳ %s ${NC}[========= ]" "$title"
    sleep 0.25
    printf "\r${YELLOW}⏳ %s ${NC}[==========] \( {GREEN}DONE! \){NC}\n" "$title"
}

# Sudo check
if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# ==========================================
# Main Menu
# ==========================================
show_menu() {
    clear
    echo
    echo -e "\( {CYAN} \){BOLD}"
    cat << 'EOF'
          ╔══════════════════════════════╗
          ║                              ║
          ║           RemVPS             ║
          ║                              ║
          ╚══════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "\( {CYAN}──────────────────────────────────────── \){NC}"
    echo
    echo -e "  \( {YELLOW}Select an option: \){NC}"
    echo
    echo -e "  \( {CYAN}[1] \){NC}  Create & Boot New Instance"
    echo -e "  \( {CYAN}[2] \){NC}  Restart Existing Instance"
    echo -e "  \( {CYAN}[3] \){NC}  Modify TCP Port Rules"
    echo -e "  \( {CYAN}[4] \){NC}  Clean Cache & Reset"
    echo -e "  \( {CYAN}[5] \){NC}  Exit"
    echo
    echo -e "\( {CYAN}──────────────────────────────────────── \){NC}"
    echo -ne "  ${WHITE}➤ Enter choice [1-5]: ${NC}"
    read -r CHOICE

    case $CHOICE in
        1) create_vps ;;
        2) restart_vps ;;
        3) configure_tcp ;;
        4) clean_vps ;;
        5) echo -e "\n\( {GREEN}  Goodbye from RemVPS. \){NC}\n"; exit 0 ;;
        *) echo -e "\( {RED}  ❌ Invalid choice. Please select 1-5. \){NC}"; sleep 1.5; show_menu ;;
    esac
}

# Create VPS
create_vps() {
    clear
    echo -e "\( {CYAN}──────────────────────────────────────── \){NC}"
    echo -e "\( {WHITE} \){BOLD}  Configure Virtual Machine${NC}"
    echo -e "\( {CYAN}──────────────────────────────────────── \){NC}"
    echo

    echo -ne "${BLUE}  ➤ RAM Size in GB (e.g. 4, 8, 16): ${NC}"
    read -r RAM_GB
    echo -ne "${BLUE}  ➤ CPU Cores (e.g. 2, 4, 8): ${NC}"
    read -r CPU_CORES
    echo -ne "${BLUE}  ➤ Disk Space to ADD in GB: ${NC}"
    read -r DISK_ADD
    echo -ne "${BLUE}  ➤ Username (default: ubuntu): ${NC}"
    read -r USER_NAME
    USER_NAME=${USER_NAME:-ubuntu}
    echo -ne "${BLUE}  ➤ Password (default: 1234): ${NC}"
    read -r USER_PASS
    USER_PASS=${USER_PASS:-1234}

    TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
    TCP_GUEST_PORT=22

    echo
    echo -e "\( {YELLOW}  Installing core dependencies... \){NC}"
    echo

    $SUDO_CMD apt-get update -y > /dev/null 2>&1
    $SUDO_CMD apt-get install -y qemu-system-x86 qemu-utils wget cloud-image-utils curl > /dev/null 2>&1

    $SUDO_CMD mkdir -p /home/daytona > /dev/null 2>&1

    if [ ! -f "/home/daytona/ubuntu22.qcow2" ]; then
        echo -e "\( {YELLOW}  📥 Downloading Ubuntu 22.04 Cloud Image... \){NC}"
        $SUDO_CMD wget -q --show-progress https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O /home/daytona/ubuntu22.qcow2
        $SUDO_CMD chmod 666 /home/daytona/ubuntu22.qcow2
    else
        echo -e "\( {GREEN}  ✅ Existing Ubuntu image found. \){NC}"
    fi

    loading_bar "Generating Cloud-Init seed"
    cat > user-data <<EOF
#cloud-config
ssh_pwauth: True
chpasswd:
  list: |
    \( {USER_NAME}: \){USER_PASS}
  expire: False
EOF

    cloud-localds seed.img user-data > /dev/null 2>&1
    loading_bar "Expanding virtual disk"
    \( SUDO_CMD qemu-img resize /home/daytona/ubuntu22.qcow2 + \){DISK_ADD}G > /dev/null 2>&1

    save_env
    boot_qemu
}

# Configure TCP
configure_tcp() {
    clear
    echo -e "\( {CYAN}──────────────────────────────────────── \){NC}"
    echo -e "\( {WHITE} \){BOLD}  TCP Port Forwarding Rules${NC}"
    echo -e "\( {CYAN}──────────────────────────────────────── \){NC}"
    echo

    if [ -f ".vps_env" ]; then
        # shellcheck source=/dev/null
        source .vps_env
    fi

    echo -e "  Current Host Port  : \( {CYAN} \){TCP_HOST_PORT:-2222}${NC}"
    echo -e "  Current Guest Port : \( {CYAN} \){TCP_GUEST_PORT:-22}${NC}"
    echo
    echo -ne "${BLUE}  ➤ New Host Port (default: 2222): ${NC}"
    read -r NEW_HOST_PORT
    TCP_HOST_PORT=${NEW_HOST_PORT:-2222}

    echo -ne "${BLUE}  ➤ Guest Port (default: 22): ${NC}"
    read -r NEW_GUEST_PORT
    TCP_GUEST_PORT=${NEW_GUEST_PORT:-22}

    save_env
    echo
    echo -e "\( {GREEN}  ✅ Port rules updated successfully. \){NC}"
    sleep 1.8
    show_menu
}

save_env() {
    cat > .vps_env <<EOF
RAM_GB=${RAM_GB:-4}
CPU_CORES=${CPU_CORES:-2}
USER_NAME=${USER_NAME:-ubuntu}
USER_PASS=${USER_PASS:-1234}
TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
TCP_GUEST_PORT=${TCP_GUEST_PORT:-22}
EOF
}

# Boot
boot_qemu() {
    if [ -f ".vps_env" ]; then
        # shellcheck source=/dev/null
        source .vps_env
    fi

    TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
    TCP_GUEST_PORT=${TCP_GUEST_PORT:-22}
    RAM_VALUE="${RAM_GB:-4}G"

    clear
    echo -e "\( {GREEN}──────────────────────────────────────── \){NC}"
    type_effect "  System ready. Starting network..." 0.012
    echo -e "\( {GREEN}──────────────────────────────────────── \){NC}"
    echo

    sshx_log=$(mktemp)
    curl -sSf https://sshx.io/get | sh -s run > "$sshx_log" 2>&1 &
    sleep 5
    SSHX_URL=$(grep -o 'https://sshx.io/s/[a-zA-Z0-9]*' "$sshx_log" | head -n 1)
    rm -f "$sshx_log"

    clear
    echo -e "\( {GREEN}──────────────────────────────────────── \){NC}"
    echo -e "\( {WHITE} \){BOLD}       RemVPS  •  Instance Active${NC}"
    echo -e "\( {GREEN}──────────────────────────────────────── \){NC}"
    echo
    echo -e "  \( {WHITE}Username  : \){NC}  \( {CYAN} \){USER_NAME:-ubuntu}${NC}"
    echo -e "  \( {WHITE}Password  : \){NC}  \( {CYAN} \){USER_PASS:-1234}${NC}"
    echo -e "  \( {WHITE}Resources : \){NC}  \( {CYAN} \){RAM_VALUE} RAM  |  \( {CPU_CORES:-2} Cores \){NC}"
    echo -e "  \( {WHITE}Port Rule : \){NC}  ${YELLOW}Host ${TCP_HOST_PORT} → Guest \( {TCP_GUEST_PORT} \){NC}"
    echo
    echo -e "\( {CYAN}──────────────────────────────────────── \){NC}"
    if [ -n "$SSHX_URL" ]; then
        echo -e "  \( {YELLOW}Live Access Link: \){NC}"
        echo -e "  ${GREEN}\( SSHX_URL \){NC}"
    else
        echo -e "  \( {RED}Tunnel still loading. Local port is ready. \){NC}"
    fi
    echo -e "\( {CYAN}──────────────────────────────────────── \){NC}"
    echo -e "  \( {WHITE}Connect: \){NC}  ssh ${USER_NAME:-ubuntu}@localhost -p ${TCP_HOST_PORT}"
    echo -e "\( {GREEN}──────────────────────────────────────── \){NC}"
    echo

    qemu-system-x86_64 \
        -hda /home/daytona/ubuntu22.qcow2 \
        -m "$RAM_VALUE" \
        -smp "${CPU_CORES:-2}" \
        -drive file=seed.img,format=raw \
        -nographic \
        -netdev user,id=net0,hostfwd=tcp::\( {TCP_HOST_PORT}-: \){TCP_GUEST_PORT} \
        -device e1000,netdev=net0
}

# Restart
restart_vps() {
    if [ -f "/home/daytona/ubuntu22.qcow2" ] && [ -f "seed.img" ]; then
        echo -e "\( {GREEN}  🔄 Restarting existing instance... \){NC}"
        sleep 1
        boot_qemu
    else
        echo -e "\( {RED}  ❌ No existing configuration found. Use option 1 first. \){NC}"
        sleep 2.5
        show_menu
    fi
}

# Clean
clean_vps() {
    echo -e "\( {RED}  ⚠️  Removing all cache files and configuration... \){NC}"
    $SUDO_CMD rm -rf user-data seed.img /home/daytona/ubuntu22.qcow2 .vps_env
    pkill -f sshx > /dev/null 2>&1 || true
    sleep 1
    echo -e "\( {GREEN}  ✅ Workspace cleaned successfully. \){NC}"
    sleep 1.8
    show_menu
}

# Start
show_menu                    ======  ====                                    ====  +=====                    
                  =========                                              =========                  
                ==============                                        ==============                
                =================                                  =================                
                ====================                            ====================                
                ======================                        ======================                
                  =======================                  =======================                  
                    +=======================            ========================                    
                ==     =======================        =======================     ==                
                ===       ======================    ======================       ===                
                =====        ===================    ===================        =====                
                ========        ================    =================       ========                
                ==========        ==============    ==============       ===========                
                ==============       ===========    ===========       ==============                
                ================      ==========    ==========      ================                
                 ==================    =========    =========   ===================                 
                   ===================  ========    ========  ===================                   
                     ===========================    ===========================                     
                         =======================    ========================                        
                           ====================      ====================                           
                              ===============          ===============                              
                                 ==========              ==========                                 
                                     ==                      ===                                    
EOF
    echo -e "${NC}"
    echo -e "\( {WHITE}                          R e m V P S \){NC}"
    echo -e "\( {CYAN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo ""
    echo -e "\( {YELLOW}  Select an option: \){NC}"
    echo ""
    echo -e "  \( {CYAN}[1] \){NC}  Create & Boot New Ubuntu Instance"
    echo -e "  \( {CYAN}[2] \){NC}  Restart Existing Instance"
    echo -e "  \( {CYAN}[3] \){NC}  Modify TCP Port Forward Rules"
    echo -e "  \( {CYAN}[4] \){NC}  Clean Cache & Reset Workspace"
    echo -e "  \( {CYAN}[5] \){NC}  Exit"
    echo ""
    echo -e "\( {CYAN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo -ne "${WHITE}  ➤ Enter Choice [1-5]: ${NC}"
    read CHOICE
    
    case $CHOICE in
        1) create_vps ;;
        2) restart_vps ;;
        3) configure_tcp ;;
        4) clean_vps ;;
        5) echo -e "\n\( {GREEN}  Goodbye from RemVPS. \){NC}\n"; exit 0 ;;
        *) echo -e "\( {RED}  ❌ Invalid choice. Please select 1-5. \){NC}"; sleep 1.5; show_menu ;;
    esac
}

# STEP 1: CONFIGURE STORAGE & DOWNLOAD CLOUD ARCHITECTURE
create_vps() {
    clear
    echo -e "\( {CYAN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo -e "\( {WHITE}  Configure Virtual Machine Specifications \){NC}"
    echo -e "\( {CYAN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo ""
    
    echo -ne "${BLUE}  ➤ RAM Size in GB (e.g. 4, 8, 16, 32): ${NC}"
    read RAM_GB
    echo -ne "${BLUE}  ➤ CPU Cores (e.g. 2, 4, 8): ${NC}"
    read CPU_CORES
    echo -ne "${BLUE}  ➤ Disk Space to ADD in GB (e.g. 10, 20): ${NC}"
    read DISK_ADD
    echo -ne "${BLUE}  ➤ Username (Default: ubuntu): ${NC}"
    read USER_NAME
    USER_NAME=${USER_NAME:-ubuntu}
    echo -ne "${BLUE}  ➤ Password (Default: 1234): ${NC}"
    read USER_PASS
    USER_PASS=${USER_PASS:-1234}
    
    TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
    TCP_GUEST_PORT=22

    echo ""
    echo -e "\( {YELLOW}  Installing core dependencies... \){NC}"
    echo ""
    
    $SUDO_CMD apt-get update -y > /dev/null 2>&1
    $SUDO_CMD apt-get install -y qemu-system-x86 qemu-utils wget cloud-image-utils curl > /dev/null 2>&1
    
    $SUDO_CMD mkdir -p /home/daytona > /dev/null 2>&1
    
    if [ ! -f "/home/daytona/ubuntu22.qcow2" ]; then
        echo -e "\( {YELLOW}  📥 Downloading Ubuntu 22.04 Cloud Image... \){NC}"
        $SUDO_CMD wget -q --show-progress https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O /home/daytona/ubuntu22.qcow2
        $SUDO_CMD chmod 666 /home/daytona/ubuntu22.qcow2
    else
        echo -e "\( {GREEN}  ✅ Existing Ubuntu image found. \){NC}"
    fi
    
    loading_bar "Generating Cloud-Init seed"
    cat <<EOF > user-data
#cloud-config
ssh_pwauth: True
chpasswd:
  list: |
    \( {USER_NAME}: \){USER_PASS}
  expire: False
EOF

    cloud-localds seed.img user-data > /dev/null 2>&1
    loading_bar "Expanding virtual disk"
    \( SUDO_CMD qemu-img resize /home/daytona/ubuntu22.qcow2 + \){DISK_ADD}G > /dev/null 2>&1
    
    save_env
    boot_qemu
}

# STEP 2: NETWORK CONTROL MODIFIER
configure_tcp() {
    clear
    echo -e "\( {CYAN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo -e "\( {WHITE}  TCP Port Forwarding Rules \){NC}"
    echo -e "\( {CYAN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo ""
    if [ -f ".vps_env" ]; then
        source .vps_env
    fi
    echo -e "  Current Host Port   : \( {CYAN} \){TCP_HOST_PORT:-2222}${NC}"
    echo -e "  Current Guest Port  : \( {CYAN} \){TCP_GUEST_PORT:-22}${NC}"
    echo ""
    echo -ne "${BLUE}  ➤ New External Host Port (Default: 2222): ${NC}"
    read NEW_HOST_PORT
    TCP_HOST_PORT=${NEW_HOST_PORT:-2222}
    
    echo -ne "${BLUE}  ➤ Internal Guest Port (Default: 22): ${NC}"
    read NEW_GUEST_PORT
    TCP_GUEST_PORT=${NEW_GUEST_PORT:-22}
    
    save_env
    echo ""
    echo -e "\( {GREEN}  ✅ Port rules updated successfully. \){NC}"
    sleep 1.8
    show_menu
}

save_env() {
    echo "RAM_GB=${RAM_GB:-32}" > .vps_env
    echo "CPU_CORES=${CPU_CORES:-4}" >> .vps_env
    echo "USER_NAME=${USER_NAME:-ubuntu}" >> .vps_env
    echo "USER_PASS=${USER_PASS:-1234}" >> .vps_env
    echo "TCP_HOST_PORT=${TCP_HOST_PORT:-2222}" >> .vps_env
    echo "TCP_GUEST_PORT=${TCP_GUEST_PORT:-22}" >> .vps_env
}

# STEP 3: BOOT
boot_qemu() {
    if [ -f ".vps_env" ]; then
        source .vps_env
    fi

    TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
    TCP_GUEST_PORT=${TCP_GUEST_PORT:-22}
    RAM_VALUE="${RAM_GB:-32}G"

    clear
    echo -e "\( {GREEN}══════════════════════════════════════════════════════════════════ \){NC}"
    type_effect "  System ready. Starting network channels..." 0.015
    echo -e "\( {GREEN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo ""
    
    sshx_log=$(mktemp)
    curl -sSf https://sshx.io/get | sh -s run > "$sshx_log" 2>&1 &
    
    sleep 5
    SSHX_URL=$(grep -o 'https://sshx.io/s/[a-zA-Z0-9]*' "$sshx_log" | head -n 1)
    rm -f "$sshx_log"

    clear
    echo -e "\( {GREEN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo -e "\( {WHITE}                    RemVPS  •  Instance Active \){NC}"
    echo -e "\( {GREEN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo ""
    echo -e "  \( {WHITE}Username   : \){NC}  \( {CYAN} \){USER_NAME:-ubuntu}${NC}"
    echo -e "  \( {WHITE}Password   : \){NC}  \( {CYAN} \){USER_PASS:-1234}${NC}"
    echo -e "  \( {WHITE}Resources  : \){NC}  \( {CYAN} \){RAM_VALUE} RAM  |  \( {CPU_CORES:-4} Cores \){NC}"
    echo -e "  \( {WHITE}Port Rule  : \){NC}  ${YELLOW}Host ${TCP_HOST_PORT} → Guest \( {TCP_GUEST_PORT} \){NC}"
    echo ""
    echo -e "\( {CYAN}────────────────────────────────────────────────────────────────── \){NC}"
    if [ ! -z "$SSHX_URL" ]; then
        echo -e "  \( {YELLOW}Live Access Link: \){NC}"
        echo -e "  ${GREEN}\( SSHX_URL \){NC}"
    else
        echo -e "  \( {RED}Tunnel still loading. Local port is ready. \){NC}"
    fi
    echo -e "\( {CYAN}────────────────────────────────────────────────────────────────── \){NC}"
    echo -e "  \( {WHITE}Connect with: \){NC}  ssh ${USER_NAME:-ubuntu}@localhost -p ${TCP_HOST_PORT}"
    echo -e "\( {GREEN}══════════════════════════════════════════════════════════════════ \){NC}"
    echo ""
    
    qemu-system-x86_64 \
        -hda /home/daytona/ubuntu22.qcow2 \
        -m $RAM_VALUE \
        -smp ${CPU_CORES:-4} \
        -drive file=seed.img,format=raw \
        -nographic \
        -netdev user,id=net0,hostfwd=tcp::\( {TCP_HOST_PORT}-: \){TCP_GUEST_PORT} \
        -device e1000,netdev=net0
}

# RESTART
restart_vps() {
    if [ -f "/home/daytona/ubuntu22.qcow2" ] && [ -f "seed.img" ]; then
        echo -e "\( {GREEN}  🔄 Restarting existing instance... \){NC}"
        sleep 1
        boot_qemu
    else
        echo -e "\( {RED}  ❌ No existing configuration found. Use option 1 first. \){NC}"
        sleep 2.5
        show_menu
    fi
}

# CLEAN
clean_vps() {
    echo -e "\( {RED}  ⚠️  Removing all cache files and configuration... \){NC}"
    $SUDO_CMD rm -rf user-data seed.img /home/daytona/ubuntu22.qcow2 .vps_env
    pkill sshx > /dev/null 2>&1
    pkill sh > /dev/null 2>&1
    sleep 1
    echo -e "\( {GREEN}  ✅ Workspace cleaned successfully. \){NC}"
    sleep 1.8
    show_menu
}

# START
show_menu
