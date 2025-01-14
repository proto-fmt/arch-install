#!/bin/bash

# Color Configuration
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper Functions
log() {
    echo -e "${CYAN}[*] ${NC}$1"
}
error() {
    echo -e "${RED}[!] Error: ${NC}$1"
    exit 1
}
success() {
    echo -e "${GREEN}[+] ${NC}$1"
}
warning() {
    echo -e "${YELLOW}[!] Warning: ${NC}$1"
}

# Check boot mode (UEFI or BIOS)
check_boot_mode() {
    log "Checking boot mode..."
    if [ -d "/sys/firmware/efi" ]; then
        BOOT_MODE="uefi"
        success "UEFI system detected"
    else
        BOOT_MODE="bios" 
        success "BIOS system detected"
    fi
}

# Check if internet is working
check_internet() {
    log "Checking internet connection..."
    if ! ping -c 1 -W 5 archlinux.org >/dev/null 2>&1; then
        error "No internet connection"
    fi
    success "Internet connection is working"
}

# Prepare disk for installation
prepare_disk() {
    log "Preparing disk for installation..."
    
    # Show available disks and get user input
    log "Available disks:"
    lsblk
    echo
    read -p "Enter target disk (e.g. /dev/sda): " DISK
    while [ ! -b "$DISK" ]; do
        error "Invalid disk. Please try again"
        read -p "Enter target disk (e.g. /dev/sda): " DISK
    done

    read -p "Enter swap partition size in GB (default: 8): " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-8}
    while ! [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]]; do
        error "Invalid size. Please enter a number"
        read -p "Enter swap partition size in GB (default: 8): " SWAP_SIZE
        SWAP_SIZE=${SWAP_SIZE:-8}
    done

    read -p "Enter root partition size in GB (default: 50): " ROOT_SIZE
    ROOT_SIZE=${ROOT_SIZE:-50}
    while ! [[ "$ROOT_SIZE" =~ ^[0-9]+$ ]]; do
        error "Invalid size. Please enter a number"
        read -p "Enter root partition size in GB (default: 50): " ROOT_SIZE
        ROOT_SIZE=${ROOT_SIZE:-50}
    done
    
    # Show current disk layout
    log "Current disk layout:"
    lsblk "$DISK"
    
    # Confirmation
    log "WARNING: This will erase all data on $DISK"
    log "Planned partition scheme:"
    if [ "$BOOT_MODE" = "uefi" ]; then
        echo "- EFI partition: 1024 MiB (FAT32)"
    else
        echo "- Boot partition: 1024 MiB (ext4)"
    fi
    echo "- Swap partition: ${SWAP_SIZE} GiB (swap)"
    echo "- Root partition: ${ROOT_SIZE} GiB (ext4)"
    echo "- Home partition: Remaining space (ext4)"
    
    read -p "Are you sure you want to continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        error "Installation aborted by user"
    fi

    # Calculate partition points
    BOOT_START="1MiB"
    BOOT_END="1025MiB"
    SWAP_START="$BOOT_END"
    SWAP_END="$((SWAP_SIZE * 1024 + 1025))MiB"
    ROOT_START="$SWAP_END"
    ROOT_END="$((SWAP_SIZE * 1024 + ROOT_SIZE * 1024 + 1025))MiB"
    HOME_START="$ROOT_END"
    HOME_END="100%"

    # Create partitions
    log "Creating partitions..."
    if [ "$BOOT_MODE" = "uefi" ]; then
        parted -s "$DISK" \
            mklabel gpt \
            mkpart "EFI" fat32 $BOOT_START $BOOT_END \
            set 1 esp on \
            mkpart "Swap" linux-swap $SWAP_START $SWAP_END \
            mkpart "Root" ext4 $ROOT_START $ROOT_END \
            mkpart "Home" ext4 $HOME_START $HOME_END
    else
        parted -s "$DISK" \
            mklabel msdos \
            mkpart primary ext4 $BOOT_START $BOOT_END \
            set 1 boot on \
            mkpart primary linux-swap $SWAP_START $SWAP_END \
            mkpart primary ext4 $ROOT_START $ROOT_END \
            mkpart primary ext4 $HOME_START $HOME_END
    fi
            
    # Format partitions
    log "Formatting partitions..."
    if [ "$BOOT_MODE" = "uefi" ]; then
        mkfs.fat -F32 "${DISK}1"
    else
        mkfs.ext4 "${DISK}1"
    fi
    mkswap "${DISK}2"
    mkfs.ext4 "${DISK}3"
    mkfs.ext4 "${DISK}4"
        
    # Mount partitions
    log "Mounting partitions..."
    mount "${DISK}3" /mnt
    if [ "$BOOT_MODE" = "uefi" ]; then
        mkdir -p /mnt/boot/efi
        mount "${DISK}1" /mnt/boot/efi
    else
        mkdir -p /mnt/boot
        mount "${DISK}1" /mnt/boot
    fi
    mkdir -p /mnt/home
    mount "${DISK}4" /mnt/home
    swapon "${DISK}2"
    
    success "Disk partitioning completed"
}

install_base() {
    log "Installing base system..."
    
    # Get package selection from user
    read -p "Install CPU microcode? (y/n, default: y): " INSTALL_MICROCODE
    INSTALL_MICROCODE=${INSTALL_MICROCODE:-y}
    INSTALL_MICROCODE=$([ "$INSTALL_MICROCODE" = "y" ] && echo 1 || echo 0)

    read -p "Install NetworkManager? (y/n, default: y): " INSTALL_NETWORK_MANAGER
    INSTALL_NETWORK_MANAGER=${INSTALL_NETWORK_MANAGER:-y}
    INSTALL_NETWORK_MANAGER=$([ "$INSTALL_NETWORK_MANAGER" = "y" ] && echo 1 || echo 0)

    read -p "Install bluetooth support? (y/n, default: n): " INSTALL_BLUETOOTH
    INSTALL_BLUETOOTH=${INSTALL_BLUETOOTH:-n}
    INSTALL_BLUETOOTH=$([ "$INSTALL_BLUETOOTH" = "y" ] && echo 1 || echo 0)

    read -p "Install wifi support? (y/n, default: n): " INSTALL_WIFI
    INSTALL_WIFI=${INSTALL_WIFI:-n}
    INSTALL_WIFI=$([ "$INSTALL_WIFI" = "y" ] && echo 1 || echo 0)

    read -p "Enter additional packages (space-separated, default: vim git wget curl): " EXTRA_PACKAGES
    EXTRA_PACKAGES=${EXTRA_PACKAGES:-"vim git wget curl"}
    
    # Prepare package list
    PACKAGES="base base-devel linux linux-firmware grub sudo $EXTRA_PACKAGES"
    
    # Add conditional packages
    [ "$BOOT_MODE" = "uefi" ] && PACKAGES="$PACKAGES efibootmgr"
    [ $INSTALL_MICROCODE -eq 1 ] && PACKAGES="$PACKAGES intel-ucode amd-ucode"
    [ $INSTALL_NETWORK_MANAGER -eq 1 ] && PACKAGES="$PACKAGES networkmanager"
    [ $INSTALL_BLUETOOTH -eq 1 ] && PACKAGES="$PACKAGES bluez bluez-utils"
    [ $INSTALL_WIFI -eq 1 ] && PACKAGES="$PACKAGES iwd wpa_supplicant"
    
    # Install packages
    pacstrap /mnt $PACKAGES
    
    success "Base system installed"
}

configure_system() {
    log "Configuring system..."

    # Get system configuration from user
    read -p "Enter hostname (default: archlinux): " HOSTNAME
    HOSTNAME=${HOSTNAME:-archlinux}
    while [[ ! $HOSTNAME =~ ^[a-zA-Z0-9-]+$ ]]; do
        error "Invalid hostname format"
        read -p "Enter hostname (default: archlinux): " HOSTNAME
        HOSTNAME=${HOSTNAME:-archlinux}
    done

    read -p "Enter username (default: user): " USERNAME
    USERNAME=${USERNAME:-user}
    while [[ ! $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]]; do
        error "Invalid username format"
        read -p "Enter username (default: user): " USERNAME
        USERNAME=${USERNAME:-user}
    done

    log "Available timezones:"
    timedatectl list-timezones | less
    read -p "Enter timezone (e.g. Europe/London): " TIMEZONE
    while [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; do
        error "Invalid timezone"
        read -p "Enter timezone (e.g. Europe/London): " TIMEZONE
    done

    log "Available keymaps:"
    localectl list-keymaps | less
    read -p "Enter keymap (default: us): " KEYMAP
    KEYMAP=${KEYMAP:-us}
    while ! localectl list-keymaps | grep -q "^${KEYMAP}$"; do
        error "Invalid keymap"
        read -p "Enter keymap (default: us): " KEYMAP
        KEYMAP=${KEYMAP:-us}
    done

    while true; do
        read -s -p "Enter root password (min 8 chars): " ROOT_PASSWORD
        echo
        read -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
        echo
        if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ] && [ ${#ROOT_PASSWORD} -ge 8 ]; then
            break
        fi
        error "Passwords don't match or too short"
    done

    while true; do
        read -s -p "Enter user password (min 8 chars): " USER_PASSWORD
        echo
        read -s -p "Confirm user password: " USER_PASSWORD_CONFIRM
        echo
        if [ "$USER_PASSWORD" = "$USER_PASSWORD_CONFIRM" ] && [ ${#USER_PASSWORD} -ge 8 ]; then
            break
        fi
        error "Passwords don't match or too short"
    done
    
    # Generate fstab
    genfstab -U /mnt > /mnt/etc/fstab
    
    # Configure system through chroot
    arch-chroot /mnt /bin/bash <<EOF
    # Timezone
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
    
    # Localization
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
    
    # Hostname
    echo "$HOSTNAME" > /etc/hostname
    echo "127.0.0.1 localhost" >> /etc/hosts
    echo "::1       localhost" >> /etc/hosts
    echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts
    
    # Users and passwords
    echo "root:$ROOT_PASSWORD" | chpasswd
    useradd -m -G wheel -s /bin/bash $USERNAME
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
    
    # Sudo configuration
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers.d/wheel
    
    # Bootloader
    if [ "$BOOT_MODE" = "uefi" ]; then
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    else
        grub-install --target=i386-pc $DISK
    fi
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # Enable services
    [ $INSTALL_NETWORK_MANAGER -eq 1 ] && systemctl enable NetworkManager
    [ $INSTALL_BLUETOOTH -eq 1 ] && systemctl enable bluetooth
EOF
    
    success "System configured"
}

# Main Installation
main() {
    clear
    log "Welcome to Arch Linux installation"
    
    while true; do
        echo
        echo "Installation steps:"
        echo "1. System checks (boot mode and internet)"
        echo "2. Disk preparation"
        echo "3. System installation and configuration"
        echo "4. Exit"
        echo
        read -p "Choose step (1-4): " step
        
        case $step in
            1)
                check_boot_mode
                check_internet
                ;;
            2)
                prepare_disk
                ;;
            3)
                install_base
                configure_system
                # Unmount everything before finishing
                log "Unmounting partitions..."
                umount -R /mnt || warning "Failed to unmount some partitions"
                success "Installation completed successfully!"
                log "Please remove the installation media and reboot."
                ;;
            4)
                log "Exiting installation..."
                exit 0
                ;;
            *)
                error "Invalid option. Please choose 1-4"
                ;;
        esac
    done
}

# Start installation
main