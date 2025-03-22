#!/bin/bash

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

if [ ! -d /sys/firmware/efi ]; then
    echo "${RED}This script must be run in an Arch Linux UEFI live environment!${RESET}"
    exit 1
fi

echo "${GREEN}Welcome to quinsaiz's Arch Linux Installer!${RESET}"

timedatectl set-ntp true

echo "${BLUE}=== Enter basic information ===${RESET}"
read -p "${YELLOW}Enter hostname: ${RESET}" HOSTNAME
read -s -p "${YELLOW}Enter root password: ${RESET}" ROOT_PASS
echo ""
read -p "${YELLOW}Enter username: ${RESET}" USERNAME
read -s -p "${YELLOW}Enter password for $USERNAME: ${RESET}" USER_PASS
echo ""

echo "${BLUE}=== Select kernel ===${RESET}"
echo "1) linux; 2) linux-zen; 3) linux-lts."
read -p "${YELLOW}Choice: ${RESET}" KERNEL
case $KERNEL in
    1) KERNEL_PKG="linux linux-headers" ;;
    2) KERNEL_PKG="linux-zen linux-zen-headers" ;;
    3) KERNEL_PKG="linux-lts linux-lts-headers" ;;
    *) echo "${RED}Invalid choice, installing linux-zen${RESET}"; KERNEL_PKG="linux-zen linux-zen-headers" ;;
esac

echo "${BLUE}=== Select disk for installation ===${RESET}"
lsblk -d -o name,type | grep disk | awk '{print "/dev/"$1 " " $2}'
read -p "${YELLOW}Disk name (e.g., /dev/sda, /dev/nvme0n1): ${RESET}" DISK

echo "${BLUE}=== Partitioning ===${RESET}"
echo "Are partitions already created and mounted? 1) Yes 2) No"
read -p "${YELLOW}Choice: ${RESET}" PARTITIONED
if [ "$PARTITIONED" == "1" ]; then
    echo "${GREEN}Skipping partitioning and mounting, proceeding to package installation...${RESET}"
else
    TOTAL_SIZE=$(parted $DISK print | grep "Disk $DISK" | awk '{print $3}' | sed 's/GB//')
    echo "Total disk size: ${TOTAL_SIZE}GB"

    echo "${BLUE}=== Partition setup ===${RESET}"
    read -p "${YELLOW}EFI size (e.g., 2G, default 512M): ${RESET}" EFI_SIZE
    EFI_SIZE=${EFI_SIZE:-512M}
    EFI_END=$(echo "$EFI_SIZE" | sed 's/[MG]//')
    if [[ "$EFI_SIZE" =~ M$ ]]; then
        EFI_END=$(echo "scale=2; $EFI_END / 1024" | bc)
    fi
    REMAINING=$(echo "scale=2; $TOTAL_SIZE - $EFI_END" | bc)

    echo "Remaining: ${REMAINING}GB"
    read -p "${YELLOW}Root (/) size (e.g., 100G, Enter for all space): ${RESET}" ROOT_SIZE
    if [ -z "$ROOT_SIZE" ]; then
        ROOT_SIZE="${REMAINING}G"
    fi
    ROOT_END=$(echo "$ROOT_SIZE" | sed 's/[MG]//')
    if [[ "$ROOT_SIZE" =~ M$ ]]; then
        ROOT_END=$(echo "scale=2; $ROOT_END / 1024" | bc)
    fi
    ROOT_END=$(echo "scale=2; $EFI_END + $ROOT_END" | bc)
    REMAINING=$(echo "scale=2; $TOTAL_SIZE - $ROOT_END" | bc)
    if [ $(echo "$ROOT_END < 10" | bc) -eq 1 ]; then
        echo "${RED}Root size must be at least 10GB!${RESET}"
        exit 1
    fi

    if [ $(echo "$REMAINING > 0" | bc) -eq 1 ]; then
        echo "Remaining: ${REMAINING}GB"
        read -p "${YELLOW}Create /home? (y/N): ${RESET}" CREATE_HOME
        case "$CREATE_HOME" in
            [Yy]|[Yy][Ee][Ss])
                read -p "${YELLOW}Home size (leave blank for all remaining space): ${RESET}" HOME_SIZE
                HOME_SIZE=${HOME_SIZE:-${REMAINING}G}
                HAS_HOME="yes"
                ;;
            *)
                echo "${GREEN}Skipping /home partition creation.${RESET}"
                HAS_HOME="no"
                ;;
        esac
    else
        HAS_HOME="no"
        echo "${YELLOW}No space left for /home, all space used for /.${RESET}"
    fi

    echo "${BLUE}=== Select filesystem ===${RESET}"
    echo "1) ext4 2) f2fs"
    read -p "${YELLOW}Choice: ${RESET}" FS_TYPE
    if [ "$FS_TYPE" == "1" ]; then
        FS="ext4"
        FS_TOOLS="e2fsprogs"
    else
        FS="f2fs"
        FS_TOOLS="f2fs-tools"
    fi

    echo "${YELLOW}Partitioning disk ${DISK}...${RESET}"
    parted -s $DISK mklabel gpt
    parted -s $DISK mkpart ESP fat32 1MiB "$EFI_SIZE"
    parted -s $DISK set 1 esp on
    parted -s $DISK mkpart root "$FS" "$EFI_SIZE" "$ROOT_END"G
    if [ "$HAS_HOME" == "yes" ]; then
        parted -s $DISK mkpart home "$FS" "$ROOT_END"G 100%
    fi

    echo "${YELLOW}Formatting partitions...${RESET}"
    if [[ "$DISK" =~ ^/dev/nvme.* ]]; then
        mkfs.vfat -F32 "${DISK}p1"
        mkfs.$FS -L "arch" "${DISK}p2"
        if [ "$HAS_HOME" == "yes" ]; then
            mkfs.$FS -L "home" "${DISK}p3"
        fi
        ROOT_PART="${DISK}p2"
        EFI_PART="${DISK}p1"
        HOME_PART="${DISK}p3"
    else
        mkfs.vfat -F32 "${DISK}1"
        mkfs.$FS -L "arch" "${DISK}2"
        if [ "$HAS_HOME" == "yes" ]; then
            mkfs.$FS -L "home" "${DISK}3"
        fi
        ROOT_PART="${DISK}2"
        EFI_PART="${DISK}1"
        HOME_PART="${DISK}3"
    fi

    echo "${YELLOW}Mounting partitions...${RESET}"
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot/efi
    mount "$EFI_PART" /mnt/boot/efi
    if [ "$HAS_HOME" == "yes" ]; then
        mkdir -p /mnt/home
        mount "$HOME_PART" /mnt/home
    fi
fi

if lscpu | grep -q "AMD"; then
    UCODE="amd-ucode"
else
    UCODE="intel-ucode"
fi

echo "${BLUE}=== Choose a GPU driver ===${RESET}"
echo "1) AMD/Intel (mesa); 2) NVIDIA (open-driver); 3) iGPU + NVIDIA (notebook)."
read -p "${YELLOW}Choice: ${RESET}" GPU
case $GPU in
    1)
        if [ "$UCODE" == "amd-ucode" ]; then 
            GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader";
        else
            GPU_PKGS="mesa vulkan-intel vulkan-icd-loader";
        fi
        MODULES="" 
        ;;
    2)
        if [ "$KERNEL" == "1" ]; then
            GPU_PKGS="nvidia-open nvidia-utils nvidia-settings vulkan-icd-loader"
        elif [ "$KERNEL" == "2" ]; then
            GPU_PKGS="nvidia-open-dkms nvidia-utils nvidia-settings vulkan-icd-loader"
        elif [ "$KERNEL" == "3" ]; then
            GPU_PKGS="nvidia-lts nvidia-utils nvidia-settings vulkan-icd-loader"
        else
            GPU_PKGS="nvidia-open-dkms nvidia-utils nvidia-settings vulkan-icd-loader"
        fi
        MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
        ;;
    3)
        if [ "$UCODE" == "amd-ucode" ]; then
            if [ "$KERNEL" == "1" ]; then
                GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader nvidia-open nvidia-utils nvidia-prime nvidia-settings"
            elif [ "$KERNEL" == "2" ]; then
                GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader nvidia-open-dkms nvidia-utils nvidia-prime nvidia-settings"
            elif [ "$KERNEL" == "3" ]; then
                GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader nvidia-lts nvidia-utils nvidia-prime nvidia-settings"
            else
                GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader nvidia-open-dkms nvidia-utils nvidia-prime nvidia-settings"
            fi
        else
            if [ "$KERNEL" == "1" ]; then
                GPU_PKGS="mesa vulkan-intel vulkan-icd-loader nvidia-open nvidia-utils nvidia-prime nvidia-settings"
            elif [ "$KERNEL" == "2" ]; then
                GPU_PKGS="mesa vulkan-intel vulkan-icd-loader nvidia-open-dkms nvidia-utils nvidia-prime nvidia-settings"
            elif [ "$KERNEL" == "3" ]; then
                GPU_PKGS="mesa vulkan-intel vulkan-icd-loader nvidia-lts nvidia-utils nvidia-prime nvidia-settings"
            else
                GPU_PKGS="mesa vulkan-intel vulkan-icd-loader nvidia-open-dkms nvidia-utils nvidia-prime nvidia-settings"
            fi
        fi
        MODULES=""
        ;;
    *) echo "${RED}Invalid choice, installing mesa${RESET}"; GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader"; MODULES="" ;;
esac

echo "${BLUE}=== Choose a graphics environment ===${RESET}"
echo "1) GNOME; 2) GNOME Minimal; 3) KDE; 4) KDE Minimal; 5) XFCE4; 6) None"
read -p "${YELLOW}Choice: ${RESET}" DE
case $DE in
    1) DE_PKGS="gnome gdm pipewire-jack"; DE_SERVICE="gdm" ;;
    2) DE_PKGS="gnome-shell gdm nautilus gnome-control-center gnome-settings-daemon gnome-session xdg-desktop-portal-gnome gvfs gvfs-mtp gnome-keyring gnome-tweaks dconf-editor gnome-terminal gnome-themes-extra gvfs-smb gvfs-nfs pipewire-jack"; DE_SERVICE="gdm" ;;
    3) DE_PKGS="plasma kde-applications sddm"; DE_SERVICE="sddm" ;;
    4) DE_PKGS="plasma-desktop sddm"; DE_SERVICE="sddm" ;;
    5) DE_PKGS="xfce4 xfce4-goodies lightdm"; DE_SERVICE="lightdm" ;;
    6) DE_PKGS=""; DE_SERVICE="" ;;
    *) echo "${RED}Invalid choice, no graphics environment${RESET}"; DE_PKGS=""; DE_SERVICE="" ;;
esac

echo "${YELLOW}Installing basic packages...${RESET}"
pacstrap -i /mnt base base-devel $KERNEL_PKG linux-firmware $UCODE $FS_TOOLS nano networkmanager $GPU_PKGS $DE_PKGS

echo "${YELLOW}Generating fstab...${RESET}"
genfstab -U /mnt >> /mnt/etc/fstab

echo "${BLUE}=== Select a language ===${RESET}"
echo "1) Ukrainian 2) English"
read -p "${YELLOW}Choice: ${RESET}" LANG
if [ "$LANG" == "1" ]; then
    LOCALE="en_US.UTF-8 UTF-8\nuk_UA.UTF-8 UTF-8"
    LANG_CONF="LANG=uk_UA.UTF-8"
    VCONSOLE="KEYMAP=ua-utf\nFONT=UniCyr_8x16"
else
    LOCALE="en_US.UTF-8 UTF-8"
    LANG_CONF="LANG=en_US.UTF-8"
    VCONSOLE="KEYMAP=us"
fi

echo "${BLUE}=== Detecting other OS ===${RESET}"
echo "Install os-prober? 1) Yes 2) No"
read -p "${YELLOW}Choice: ${RESET}" OSPROBER
if [ "$OSPROBER" == "1" ]; then
    OSPROBER_PKG="os-prober"
else
    OSPROBER_PKG=""
fi

echo "${YELLOW}Setting up the system in chroot...${RESET}"
arch-chroot /mnt /bin/bash <<EOF

ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime
hwclock --systohc

echo -e "$LOCALE" > /etc/locale.gen
locale-gen
echo "$LANG_CONF" > /etc/locale.conf
echo -e "$VCONSOLE" > /etc/vconsole.conf

echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$HOSTNAME.localdomain $HOSTNAME" > /etc/hosts

sed -i "s/MODULES=()/MODULES=($MODULES)/" /etc/mkinitcpio.conf
sed -i 's|^HOOKS=(.*)|HOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)|' /etc/mkinitcpio.conf
echo -e "COMPRESSION=\"lz4\"\nCOMPRESSION_OPTIONS=(-9)" >> /etc/mkinitcpio.conf
mkinitcpio -P

sed -i '/^#\[multilib\]/,/^#\Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

pacman -Sy --noconfirm grub efibootmgr $OSPROBER_PKG
grub-install --target=x86_64-efi --efi-directory=/boot/efi $DISK
if [ "$OSPROBER" == "1" ]; then
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

if [ "$GPU" == "3" ]; then
    mkdir -p /etc/X11/xorg.conf.d
    echo -e 'Section "OutputClass"\n    Identifier "nvidia"\n    MatchDriver "nvidia-drm"\n    Driver "nvidia"\n    Option "PrimaryGPU" "no"\nEndSection' > /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf
    #echo "${GREEN}Make sure that /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf has the correct contents:${RESET}"
    #cat /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf
fi

echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager

echo "${BLUE}=== Install additional packages? ===${RESET}"
echo "1) Yes 2) No"
read -p "${YELLOW}Choice: ${RESET}" INSTALL_EXTRAS
if [ "$INSTALL_EXTRAS" == "1" ]; then
    pacman -S --noconfirm firefox firefox-i18n-uk qbittorrent vlc neofetch btop bash-completion steam

    if [ "$DE" == "1" ] || [ "$DE" == "2" ]; then
        echo "${YELLOW}Installing GNOME-specific additional packages...${RESET}"
        pacman -S --noconfirm gnome-browser-connector gnome-tweaks adw-gtk-theme
    fi

    case $GPU in
        1)
            if [ "$UCODE" == "amd-ucode" ]; then
                echo "${YELLOW}Installing AMD-specific multimedia drivers...${RESET}"
                pacman -S --noconfirm lib32-mesa lib32-vulkan-radeon lib32-vulkan-icd-loader ffmpeg v4l-utils libva-mesa-driver lib32-libva-mesa-driver libva lib32-libva libva-utils
            else
                echo "${YELLOW}Installing Intel-specific multimedia drivers...${RESET}"
                pacman -S --noconfirm lib32-mesa lib32-vulkan-intel lib32-vulkan-icd-loader ffmpeg v4l-utils libva-mesa-driver lib32-libva-mesa-driver libva lib32-libva libva-utils
            fi
            ;;
        2)
            echo "${YELLOW}Installing NVIDIA-specific multimedia drivers...${RESET}"
            pacman -S --noconfirm lib32-nvidia-utils lib32-vulkan-icd-loader ffmpeg v4l-utils libva lib32-libva libva-utils
            ;;
        3)
            if [ "$UCODE" == "amd-ucode" ]; then
                echo "${YELLOW}Installing hybrid AMD + NVIDIA multimedia drivers...${RESET}"
                pacman -S --noconfirm lib32-mesa lib32-vulkan-radeon lib32-vulkan-icd-loader lib32-nvidia-utils ffmpeg v4l-utils libva-mesa-driver lib32-libva-mesa-driver libva lib32-libva libva-utils
            else
                echo "${YELLOW}Installing hybrid Intel + NVIDIA multimedia drivers...${RESET}"
                pacman -S --noconfirm lib32-mesa lib32-vulkan-intel lib32-vulkan-icd-loader lib32-nvidia-utils ffmpeg v4l-utils libva-mesa-driver lib32-libva-mesa-driver libva lib32-libva libva-utils
            fi
            ;;
        *)
            echo "${RED}No GPU choice detected, installing AMD defaults...${RESET}"
            pacman -S --noconfirm lib32-mesa lib32-vulkan-radeon lib32-vulkan-icd-loader ffmpeg v4l-utils libva-mesa-driver lib32-libva-mesa-driver libva lib32-libva libva-utils
            ;;
    esac
fi

echo "${BLUE}=== Create swap? ===${RESET}"
echo "1) Yes 2) No"
read -p "${YELLOW}Choice: ${RESET}" CREATE_SWAP
if [ "$CREATE_SWAP" == "1" ]; then
    echo "1) zram 2) swapfile"
    read -p "${YELLOW}Choose swap type: ${RESET}" SWAP_TYPE
    if [ "$SWAP_TYPE" == "1" ]; then
        echo "${YELLOW}Setting up zram...${RESET}"
        pacman -S --noconfirm zram-generator
        echo -e "[zram0]\nzram-size = min(ram / 2, 4096)\ncompression-algorithm = zstd" > /etc/systemd/zram-generator.conf
        systemctl enable systemd-zram-setup@zram0.service
    elif [ "$SWAP_TYPE" == "2" ]; then
        read -p "${YELLOW}Swap file size (e.g., 2G or 512M, default 4G): ${RESET}" SWAP_SIZE
        SWAP_SIZE=${SWAP_SIZE:-4G}
        echo "${YELLOW}Creating swapfile...${RESET}"
        if [[ "$SWAP_SIZE" =~ G$ ]]; then
            COUNT=$(echo "$SWAP_SIZE" | sed 's/G//' | awk '{print $1 * 1024}')
        elif [[ "$SWAP_SIZE" =~ M$ ]]; then
            COUNT=$(echo "$SWAP_SIZE" | sed 's/M//')
        else
            COUNT=$(echo "$SWAP_SIZE" | awk '{print $1 * 1024}')
        fi
        dd if=/dev/zero of=/swapfile bs=1M count=$COUNT status=progress
        #fallocate -l "$SWAP_SIZE" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "/swapfile none swap defaults 0 0" >> /etc/fstab
        echo "${YELLOW}Configuring swappiness...${RESET}"
        echo -e "vm.swappiness=10\nvm.vfs_cache_pressure=50" > /etc/sysctl.d/99-sysctl.conf
    else
        echo "${RED}Invalid swap type, skipping...${RESET}"
    fi
fi

if [ -n "$DE_SERVICE" ]; then
    systemctl enable $DE_SERVICE
fi

EOF

echo "${GREEN}Installation complete! Unmount and reboot...${RESET}"
umount -R /mnt
echo "${YELLOW}Eject media and press Enter to reboot${RESET}"
read
reboot