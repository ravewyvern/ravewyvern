#!/bin/bash
#
# Arch Linux Installation Script
#
# WARNING: This script is designed to wipe a disk and install Arch Linux.
# Review the configuration variables and the script itself carefully before running.
#

# --- Script Configuration ---
# Set your desired hostname, username, and password.
# Be aware of shell special characters if you change the password.
HOSTNAME="RavesArchLinux"
USERNAME="ravewyvern"
PASSWORD="igf78:b"

# Define the target disk and partitions.
# !! THIS DISK WILL BE WIPED !!
DISK="/dev/nvme0n1"
EFI_PARTITION="${DISK}p1"
ROOT_PARTITION="${DISK}p2"

# Set the keyboard layout for the TTY.
KEYMAP="us"

# --- Safety & Confirmation ---
# Exit immediately if a command exits with a non-zero status.
set -e

echo "======================================================"
echo "          ARCH LINUX INSTALLATION SCRIPT              "
echo "======================================================"
echo
echo "This script will install Arch Linux with the following configuration:"
echo "  - Hostname:       ${HOSTNAME}"
echo "  - Username:       ${USERNAME}"
echo "  - Target Disk:    ${DISK}"
echo "  - EFI Partition:  ${EFI_PARTITION}"
echo "  - Root Partition: ${ROOT_PARTITION}"
echo "  - TTY Keymap:     ${KEYMAP}"
echo
echo "WARNING: ALL DATA ON ${DISK} WILL BE PERMANENTLY DELETED."
read -p "Type 'DELETE' to confirm and continue: " CONFIRMATION
if [ "$CONFIRMATION" != "DELETE" ]; then
    echo "Confirmation not received. Aborting installation."
    exit 1
fi

loadkeys ${KEYMAP}

# --- Pre-installation ---
echo "--> Synchronizing system clock..."
timedatectl set-ntp true

echo "--> Wiping disk and creating partitions on ${DISK}..."
# Wipe existing partition table and signatures to ensure a clean slate.
sgdisk --zap-all "${DISK}"
wipefs -a "${DISK}"

# Create new GPT partition table
sgdisk -o "${DISK}"

# Create partitions: 550M for EFI, and the rest for the root filesystem.
sgdisk -n 1:0:+550M -t 1:ef00 "${DISK}" # EFI System Partition
sgdisk -n 2:0:0 -t 2:8300 "${DISK}"   # Linux filesystem (root)

echo "--> Formatting partitions..."
mkfs.fat -F 32 "${EFI_PARTITION}"
mkfs.ext4 "${ROOT_PARTITION}"

echo "--> Mounting file systems..."
mount "${ROOT_PARTITION}" /mnt

echo "--> mounting disks..."
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
# Unmount the root fs
umount /mnt
# Mount the root and home subvolume. If you don't want compression just remove the compress option.
mount -o compress=zstd,subvol=@ /dev/nvme0n1p2 /mnt
mkdir -p /mnt/home
mount -o compress=zstd,subvol=@home /dev/nvme0n1p2 /mnt/home
mkdir -p /mnt/efi
mount /dev/nvme0n1p1 /mnt/efi

# --- Installation ---
echo "--> Installing base system and essential packages..."
# We install both intel-ucode and amd-ucode for broader compatibility.
pacstrap -K /mnt base base-devel linux linux-firmware git btrfs-progs grub efibootmgr grub-btrfs inotify-tools timeshift vim networkmanager pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber reflector zsh zsh-completions zsh-autosuggestions openssh man sudo

echo "--> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- System Configuration (chroot) ---
echo "--> Entering chroot and configuring the system..."
arch-chroot /mnt <<EOF
set -e # Exit on error within chroot

echo "--> Setting timezone (America/Los_Angeles)..."
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
hwclock --systohc

echo "--> Setting locale to en_US.UTF-8..."
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "--> Setting TTY keyboard layout..."
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "--> Setting hostname and hosts file..."
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${HOSTNAME}
HOSTS

echo "--> Setting root password..."
echo "root:${PASSWORD}" | chpasswd

echo "--> Creating user ${USERNAME} and setting password..."
useradd -m -G wheel "${USERNAME}"
echo "${USERNAME}:${PASSWORD}" | chpasswd

echo "--> Granting sudo privileges to the 'wheel' group..."
# Uncomment the '%wheel ALL=(ALL:ALL) ALL' line to allow users in this group to use sudo.
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "--> Installing and configuring GRUB bootloader..."
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "--> Enabling NetworkManager service..."
systemctl enable NetworkManager

EOF
# End of chroot commands

# --- Finalization ---
echo "--> Unmounting all partitions..."
umount -R /mnt

echo "======================================================"
echo "             INSTALLATION COMPLETE!                   "
echo "======================================================"
echo
echo "You can now reboot the system. Please remove the installation media."
echo "To reboot now, type: reboot"
