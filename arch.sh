#!/bin/bash
# Встановлення Arch без автоматичної розбивки диску

# Кольори
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Установка дати і часу
timedatectl set-ntp true

# Вибір ядра
read -rp "Select kernel for installation: 1 - linux, 2 - linux-lts, 3 - linux-zen: " kernel_choice
case "$kernel_choice" in
    1)
        kernel_packages="linux"
        ;;
    2)
        kernel_packages="linux-lts"
        ;;
    3)
        kernel_packages="linux-zen"
        ;;
    *)
        echo -e "${RED}✗${NC} Invalid kernel choice. Exiting."
        exit 1
        ;;
esac

# Визначення мікрокоду на основі постачальника процесора
cpu_vendor=$(grep -i 'vendor_id' /proc/cpuinfo | head -n 1 | awk '{print $3}')

if [[ "$cpu_vendor" == "GenuineIntel" || "$cpu_vendor" == "Intel" ]]; then
    microcode="intel-ucode iucode-tool"
elif [[ "$cpu_vendor" == "AuthenticAMD" || "$cpu_vendor" == "AMD" ]]; then
    microcode="amd-ucode"
else
    echo -e "${RED}✗${NC} Unknown CPU vendor ($cpu_vendor). Exiting."
    exit 1
fi

echo -e "${GREEN}✓${NC} CPU vendor detected: $cpu_vendor"
echo "Microcode packages: $microcode"

# Встановлення базової системи
pacstrap -i /mnt base base-devel $kernel_packages $kernel_packages-headers linux-firmware $microcode e2fsprogs f2fs-tools

# Введення hostname
while true; do
    read -rp "Enter hostname PC (only letters, numbers, and hyphens are allowed): " hostname
    if [[ "$hostname" =~ ^[a-zA-Z0-9]+([a-zA-Z0-9-]*[a-zфкA-Z0-9]+)?$ ]]; then
        break
    else
        echo -e "${RED}✗${NC} Invalid hostname. Please use only letters, numbers, and hyphens. Hostname cannot start or end with a hyphen."
    fi
done

# Налаштування системи
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash << EOF
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    echo "uk_UA.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen

    echo "LANG=uk_UA.UTF-8" > /etc/locale.conf
    
    echo -e "KEYMAP=ua-utf\nFONT=UniCyr_8x16" > /etc/vconsole.conf
    
    echo "$hostname" > /etc/hostname

    echo "127.0.0.1 localhost" >> /etc/hosts
    echo "::1       localhost" >> /etc/hosts
    echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts
    
    ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime
    hwclock --systohc

    mkinitcpio -P
EOF

# Налаштування користувача
read -rp "Enter new root password: " root_password
echo "root:$root_password" | arch-chroot /mnt chpasswd
echo -e "${GREEN}✓ ${NC}Root password changed successfully."

read -rp "Enter your name (username): " username
arch-chroot /mnt /bin/bash << EOF
    useradd -m -G wheel -s /bin/bash "$username"
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
EOF

read -rp "Enter your user password: " user_password
echo "$username:$user_password" | arch-chroot /mnt chpasswd
echo -e "${GREEN}✓ ${NC}$username password set successfully."

# Встановлення інтернет утиліт
arch-chroot /mnt pacman -S --noconfirm dhcpcd dhclient networkmanager

# Встановлення grub та os-prober
arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
read -rp "Specify the disk (not partition) on which to install grub: " install_grub
read -rp "Do you want to install and enable os-prober to detect other operating systems? (Y/n): " install_os_prober

# Передача змінних до arch-chroot
arch-chroot /mnt /bin/bash << EOF
    GREEN='\033[0;32m'
    NC='\033[0m'

    # Установка os-prober, якщо необхідно
    if [[ -z "$install_os_prober" || "$install_os_prober" =~ ^[Yy]$ ]]; then
        pacman -S --noconfirm os-prober
        echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
        echo -e "${GREEN}✓ ${NC}os-prober enabled."
    fi

    # Встановлення GRUB
    grub-install $install_grub
    grub-mkconfig -o /boot/grub/grub.cfg
    echo -e "${GREEN}✓ ${NC}Grub installed and configured on ${install_grub}."
EOF

# Розкоментувати секцію [multilib] & ParallelDownloads
arch-chroot /mnt /bin/bash << EOF 
    sed -i '/^#\[multilib\]/s/^#//' /etc/pacman.conf
    sed -i '/^\[multilib\]/,/^\[/{s/^#Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/}' /etc/pacman.conf
    
    sed -i '/^#ParallelDownloads/s/^#//' /etc/pacman.conf
    sed -i 's/^ParallelDownloads =.*/ParallelDownloads = 10/' /etc/pacman.conf
EOF

# Оновлення системи та встановлення пакетів
echo "Check Arch updates..."
arch-chroot /mnt pacman -Syu

# Вибір драйверів
read -rp "Select drivers for installation: 1 - AMD (amdgpu), 2 - NVIDIA Proprietary, Enter - Skip: " driver_choice
case "$driver_choice" in
    1)
        extra_packages="xf86-video-amdgpu mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader lib32-vulkan-icd-loader libva-mesa-driver lib32-libva-mesa-driver libva lib32-libva libva-utils vulkan-tools v4l-utils ffmpeg mesa-utils"
        ;;
    2)
        extra_packages="nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader lib32-opencl-nvidia opencl-nvidia libxnvctrl  "
        ;;
    *)
        echo "Skipped graphics driver..."
        extra_packages=""
        ;;
esac
arch-chroot /mnt pacman -S $extra_packages

# Оновлення конфігурацій і перезбір ядра
arch-chroot /mnt /bin/bash << EOF
    if [[ "$driver_choice" == "1" ]]; then
        sed -i 's/^MODULES=.*$/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
        echo "Kernel modules updated for AMD."
        
        mkinitcpio -P
        echo "Kernel rebuilt for AMD."
    elif [[ "$driver_choice" == "2" ]]; then
        sed -i 's/^MODULES=.*$/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        echo "Kernel modules updated for NVIDIA."

        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"nvidia-drm.modeset=1\"" >> /etc/default/grub
        grub-mkconfig -o /boot/grub/grub.cfg
        echo "GRUB updated for NVIDIA."

        mkinitcpio -P
        echo "Kernel rebuilt for NVIDIA."
    fi
EOF

# Вибір графічного середовища
read -rp "Select desktop environment for installation: 1 - GNOME + GDM, 2 - KDE Plasma + SDDM, Enter - Skip: " de_choice
case "$de_choice" in
    1)
        de_packages="gnome gdm"
        ;;
    2)
        de_packages="plasma-desktop sddm"
        ;;
    *)
        echo "Skipped desktop environment..."
        de_packages=""
        ;;
esac
arch-chroot /mnt pacman -S $de_packages

# Перевірка, чи було встановлено графічне середовище
if [[ "$de_choice" == "1" ]]; then
    arch-chroot /mnt systemctl enable gdm
    echo -e "${GREEN}✓ ${NC}Gnome and GDM installed."
elif [[ "$de_choice" == "2" ]]; then
    arch-chroot /mnt systemctl enable sddm
    echo -e "${GREEN}✓ ${NC}KDE Plasma and SDDM installed."
else
    echo -e "${GREEN}✓ ${NC}No desktop environment selected or skipped."
fi

# Встановлення програм та активація сервісів
echo "Programs install..."
arch-chroot /mnt pacman -S --noconfirm dosfstools ntfs-3g nano git btop neofetch bash-completion zsh zsh-completions power-profiles-daemon network-manager-applet
echo "Programs install v2..."
arch-chroot /mnt pacman -S firefox firefox-i18n-uk qbittorrent btop gnome-browser-connector gnome-tweaks ufw gufw
echo "Audio install..."
arch-chroot /mnt pacman -S --noconfirm alsa-utils pipewire pipewire-pulse pipewire-alsa wireplumber easyeffects lsp-plugins lsp-plugins-lv2 lsp-plugins-vst lsp-plugins-vst3 calf mda.lv2
echo "Fonts install..."
arch-chroot /mnt pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-firacode-nerd ttf-ubuntu-font-family 
echo "Game utils install..."
arch-chroot /mnt pacman -S gamemode lib32-gamemode mangohud lib32-mangohud goverlay
arch-chroot /mnt /bin/bash << EOF
    echo "Activate and configure the services..."
    systemctl enable ufw power-profiles-daemon NetworkManager
    usermod -aG gamemode $(whoami)
    ufw default deny incoming
    ufw default allow outgoing
    echo "✓ Firewall installed successfully."
EOF

# Налаштування Swapfile
read -rp "Do you want to create a swap file? (Y/n): " create_swapfile

if [[ -z "$create_swapfile" || "$create_swapfile" =~ ^[Yy]$ ]]; then
    read -rp "Enter swap file size in megabytes (e.g., 512): " swapfile_size_mb
fi

arch-chroot /mnt /bin/bash << EOF
    GREEN='\033[0;32m'
    NC='\033[0m'

    if [[ -z "$create_swapfile" || "$create_swapfile" =~ ^[Yy]$ ]]; then
        swapfile_size_bytes=$((swapfile_size_mb * 1024 * 1024))
        fallocate -l "\$swapfile_size_bytes" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap defaults 0 0' >> /etc/fstab
        echo -e "vm.swappiness=10\nvm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-sysctl.conf
        echo -e "${GREEN}✓ ${NC}Swap file successfully created."
    fi
EOF

# Налаштування Gnome
read -rp "Do you want to apply Gnome customizations? (y/N): " apply_gnome
if [[ "$apply_gnome" =~ ^[Yy]$ ]]; then
    arch-chroot /mnt /bin/bash << EOF
        gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2
        gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Shift>Alt_L']"
        gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Alt>Shift_L']"
EOF
    echo -e "${GREEN}✓${NC} Gnome customizations applied successfully."
else
    echo -e "${RED}✗${NC} Gnome customizations skipped."
fi

umount -R /mnt
echo -e "${GREEN}✓${NC} Installation complete. Please reboot the system."
