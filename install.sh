#!/bin/bash

# Add these safety flags at the beginning
set -euo pipefail
IFS=$'\n\t'

# Global variables
DISK=""
DISK_SIZE_GB=0
HOSTNAME="archlinux"
USERNAME=""
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
KEYMAP="us"
PACKAGES="base base-devel linux linux-firmware networkmanager grub efibootmgr"
LOG_FILE="/var/log/arch_install.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS: $1"
} 

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    log "ERROR: $1"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    info "Cleaning up..."
    # Ensure all partitions are unmounted
    umount -R /mnt 2>/dev/null || true
    swapoff "${DISK}2" 2>/dev/null || true
    if [ $exit_code -ne 0 ]; then
        error "Installation failed with exit code $exit_code"
    fi
    exit $exit_code
}

# Set cleanup trap
trap cleanup EXIT

# Check system requirements
check_requirements() {
    info "Checking system requirements..."
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    }

    # Check if running on Arch Linux
    if [ ! -f /etc/arch-release ]; then
        error "This script must be run on Arch Linux live environment"
        exit 1
    }

    # Check for required tools
    local required_tools=("wget" "curl" "parted" "mkfs.ext4" "mkfs.fat" "mkswap" "pacstrap" "arch-chroot")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
}

# Check boot mode
check_boot_mode() {
    info "Checking boot mode..."
    if [ -d /sys/firmware/efi/efivars ]; then
        success "System is booted in UEFI mode"
    else
        error "System is not booted in UEFI mode"
        exit 1
    fi
}

# Check internet connection
check_internet() {
    info "Checking internet connection..."
    if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
        error "No internet connection available"
        exit 1
    fi
    success "Internet connection is available"
}

# Check and update system clock
check_clock() {
    info "Updating system clock..."
    timedatectl set-ntp true
    sleep 2
    if ! timedatectl status | grep -q "System clock synchronized: yes"; then
        warning "System clock might not be synchronized"
    else
        success "System clock is synchronized"
    fi
}

# Select installation disk
select_disk() {
    info "Available disks:"
    local available_disks
    available_disks=$(lsblk -lpdo NAME,SIZE,TYPE,MODEL | grep "disk")
    
    if [ -z "$available_disks" ]; then
        error "No available disks found"
        exit 1
    }

    echo "$available_disks"
    echo
    read -rp "Enter the full path of the disk to use (e.g., /dev/sda): " DISK

    if [ ! -b "$DISK" ]; then
        error "Invalid disk: $DISK"
        exit 1
    }

    # Get disk size in GB
    DISK_SIZE_GB=$(lsblk -lndo SIZE "$DISK" | sed 's/G//')
    
    echo "WARNING: All data on $DISK will be destroyed!"
    read -rp "Are you sure you want to continue? [y/N] " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        error "Installation cancelled by user"
        exit 1
    fi
}

# Prepare disk for installation
prepare_disk() {
    info "Preparing disk $DISK..."

    # Use bc with better precision
    BC_ENV_ARGS="scale=3"
    export BC_ENV_ARGS

    # Securely wipe disk
    info "Securely wiping disk..."
    if command -v blkdiscard >/dev/null 2>&1; then
        blkdiscard "$DISK" 2>/dev/null || true
    else
        dd if=/dev/zero of="$DISK" bs=1M count=100 status=none
        dd if=/dev/zero of="$DISK" bs=1M seek=$((DISK_SIZE_GB * 1024 - 100)) count=100 status=none
    fi

    # Create partition table
    info "Creating partition table..."
    parted -s "$DISK" mklabel gpt

    # Calculate partition sizes
    local efi_size=512
    local swap_size
    if [ "$DISK_SIZE_GB" -le 8 ]; then
        swap_size=$DISK_SIZE_GB
    else
        swap_size=$(echo "sqrt($DISK_SIZE_GB * 1024)" | bc)
    fi
    swap_size=${swap_size%.*}

    # Create partitions
    parted -s "$DISK" \
        mkpart primary fat32 1MiB ${efi_size}MiB \
        mkpart primary linux-swap ${efi_size}MiB $((efi_size + swap_size))MiB \
        mkpart primary ext4 $((efi_size + swap_size))MiB 100%

    # Format partitions
    info "Formatting partitions..."
    mkfs.fat -F32 "${DISK}1"
    mkswap "${DISK}2"
    mkfs.ext4 -F "${DISK}3"

    # Mount partitions
    info "Mounting partitions..."
    mount "${DISK}3" /mnt
    mkdir -p /mnt/boot/efi
    mount "${DISK}1" /mnt/boot/efi
    swapon "${DISK}2"

    success "Disk preparation completed"
}

# Install base system
install_base() {
    info "Installing base system..."

    # Update mirrorlist
    info "Updating mirrorlist..."
    curl -s "https://archlinux.org/mirrorlist/?country=all&protocol=https&use_mirror_status=on" | \
        sed -e 's/^#Server/Server/' -e '/^#/d' | \
        rankmirrors -n 5 - > /etc/pacman.d/mirrorlist

    # Install packages with retry mechanism
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if pacstrap /mnt $PACKAGES; then
            success "Base system installed successfully"
            break
        else
            warning "Attempt $attempt of $max_attempts failed"
            if [ $attempt -eq $max_attempts ]; then
                error "Failed to install base system after $max_attempts attempts"
                exit 1
            fi
            sleep 5
            ((attempt++))
        fi
    done

    # Generate fstab
    info "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure the installed system
configure_system() {
    info "Configuring system..."

    # Validate passwords
    validate_password() {
        local pass="$1"
        if [[ ${#pass} -lt 8 ]]; then
            return 1
        elif ! [[ "$pass" =~ [A-Z] ]]; then
            return 1
        elif ! [[ "$pass" =~ [a-z] ]]; then
            return 1
        elif ! [[ "$pass" =~ [0-9] ]]; then
            return 1
        fi
        return 0
    }

    # Set root password
    local root_password
    while true; do
        read -rsp "Enter root password: " root_password
        echo
        if validate_password "$root_password"; then
            break
        else
            warning "Password must be at least 8 characters and contain uppercase, lowercase, and numbers"
        fi
    done

    # Create user
    read -rp "Enter username: " USERNAME
    local user_password
    while true; do
        read -rsp "Enter password for $USERNAME: " user_password
        echo
        if validate_password "$user_password"; then
            break
        else
            warning "Password must be at least 8 characters and contain uppercase, lowercase, and numbers"
        fi
    done

    # Configure system using arch-chroot
    arch-chroot /mnt /bin/bash <<EOF
    # Set timezone
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc

    # Set locale
    echo "$LOCALE UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=$LOCALE" > /etc/locale.conf

    # Set keyboard layout
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

    # Set hostname
    echo "$HOSTNAME" > /etc/hostname
    echo "127.0.0.1 localhost" >> /etc/hosts
    echo "::1       localhost" >> /etc/hosts
    echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

    # Set root password
    echo "root:$root_password" | chpasswd

    # Create user
    useradd -m -G wheel -s /bin/bash "$USERNAME"
    echo "$USERNAME:$user_password" | chpasswd
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

    # Install and configure bootloader
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg

    # Enable services
    systemctl enable NetworkManager
EOF

    success "System configuration completed"
}

# Main installation process
main() {
    local -a steps=(
        "check_requirements"
        "check_boot_mode"
        "check_internet"
        "check_clock"
        "select_disk"
        "prepare_disk"
        "install_base"
        "configure_system"
    )
    
    local total_steps=${#steps[@]}
    local current_step=0

    info "Starting Arch Linux installation..."
    
    for step in "${steps[@]}"; do
        ((current_step++))
        info "($current_step/$total_steps) Executing: ${step//_/ }"
        $step
    done

    success "Installation completed successfully!"
    info "You can now reboot your system"
}

# Start installation
main
