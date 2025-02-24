#!/bin/bash

# Налаштування кольорів
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# Перевірка запуску в live-середовищі
if [ ! -d /sys/firmware/efi ]; then
    echo "${RED}This script must be run in an Arch Linux UEFI live environment!${RESET}"
    exit 1
fi

echo "${GREEN}Welcome to quinsaiz's Arch Linux Installer!${RESET}"

# Синхронізація часу
timedatectl set-ntp true

# Запит базових даних
echo "${BLUE}=== Enter basic information ===${RESET}"
read -p "${YELLOW}Enter hostname: ${RESET}" HOSTNAME
read -s -p "${YELLOW}Enter root password: ${RESET}" ROOT_PASS
echo
read -p "${YELLOW}Enter username: ${RESET}" USERNAME
read -s -p "${YELLOW}Enter password for $USERNAME: ${RESET}" USER_PASS
echo

# Вибір ядра
echo "${BLUE}=== Select kernel ===${RESET}"
echo "1) linux 2) linux-zen 3) linux-lts"
read -p "${YELLOW}Choice: ${RESET}" KERNEL
case $KERNEL in
    1) KERNEL_PKG="linux linux-headers" ;;
    2) KERNEL_PKG="linux-zen linux-zen-headers" ;;
    3) KERNEL_PKG="linux-lts linux-lts-headers" ;;
    *) echo "${RED}Invalid choice, installing linux-zen${RESET}"; KERNEL_PKG="linux-zen linux-zen-headers" ;;
esac

# Вибір диска
echo "${BLUE}=== Select disk for installation ===${RESET}"
lsblk -d -o name,type | grep disk
read -p "${YELLOW}Disk name (e.g., /dev/sda, /dev/nvme0n1): ${RESET}" DISK
TOTAL_SIZE=$(parted $DISK print | grep "Disk $DISK" | awk '{print $3}' | sed 's/GB//')
echo "Total disk size: ${TOTAL_SIZE}GB"

# Вибір розмірів розділів
echo "${BLUE}=== Partition setup ===${RESET}"
read -p "${YELLOW}EFI size (e.g., 2G, default 512M): ${RESET}" EFI_SIZE
EFI_SIZE=${EFI_SIZE:-512M}
EFI_END=$(echo "$EFI_SIZE" | sed 's/[MG]//')
REMAINING=$(echo "$TOTAL_SIZE - $EFI_END" | bc)

echo "Remaining: ${REMAINING}GB"
read -p "${YELLOW}Root (/) size (e.g., 100G): ${RESET}" ROOT_SIZE
ROOT_SIZE=${ROOT_SIZE:-20G}
ROOT_END=$(echo "$EFI_END + $(echo $ROOT_SIZE | sed 's/[MG]//')" | bc)
REMAINING=$(echo "$TOTAL_SIZE - $ROOT_END" | bc)

echo "Remaining: ${REMAINING}GB"
read -p "${YELLOW}Create /home? (y/n): ${RESET}" CREATE_HOME
if [ "$CREATE_HOME" == "y" ]; then
    read -p "${YELLOW}Home size (leave blank for all remaining space): ${RESET}" HOME_SIZE
    HOME_SIZE=${HOME_SIZE:-${REMAINING}G}
    HAS_HOME="yes"
else
    HAS_HOME="no"
fi

# Вибір файлової системи
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

# Розмітка диска
echo "${YELLOW}Partitioning disk ${DISK}...${RESET}"
parted -s $DISK mklabel gpt
parted -s $DISK mkpart ESP fat32 1MiB $EFI_SIZE
parted -s $DISK set 1 esp on
parted -s $DISK mkpart root $FS $EFI_SIZE $ROOT_END
if [ "$HAS_HOME" == "yes" ]; then
    parted -s $DISK mkpart home $FS $ROOT_END 100%
fi

# Форматування розділів
echo "${YELLOW}Formatting partitions...${RESET}"
if [[ "$DISK" =~ ^/dev/nvme.* ]]; then
    mkfs.vfat -F32 "${DISK}p1"
    mkfs.$FS -L "arch" "${DISK}p2"
    if [ "$HAS_HOME" == "yes" ]; then
        mkfs.$FS -L "home" "${DISK}p3"
    fi
else
    mkfs.vfat -F32 "${DISK}1"
    mkfs.$FS -L "arch" "${DISK}2"
    if [ "$HAS_HOME" == "yes" ]; then
        mkfs.$FS -L "home" "${DISK}3"
    fi
fi

# Монтування
echo "${YELLOW}Mounting partitions...${RESET}"
if [[ "$DISK" =~ ^/dev/nvme.* ]]; then
    ROOT_PART="${DISK}p2"
    EFI_PART="${DISK}p1"
    HOME_PART="${DISK}p3"
else
    ROOT_PART="${DISK}2"
    EFI_PART="${DISK}1"
    HOME_PART="${DISK}3"
fi

mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
if [ "$HAS_HOME" == "yes" ]; then
    mkdir -p /mnt/home
    mount "$HOME_PART" /mnt/home
fi

# Визначення процесора
if lscpu | grep -q "AMD"; then
    UCODE="amd-ucode"
else
    UCODE="intel-ucode"
fi

# Вибір відеокарти
echo "${BLUE}=== Виберіть драйвери GPU ===${RESET}"
echo "1) AMD (mesa) 2) NVIDIA (nvidia-open-dkms) 3) AMD+NVIDIA (гібрид)"
read -p "${YELLOW}Вибір: ${RESET}" GPU
case $GPU in
    1) GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader"; MODULES="amdgpu" ;;
    2) GPU_PKGS="nvidia-open-dkms nvidia-utils nvidia-settings vulkan-icd-loader"; MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm";;
    3) GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader xf86-video-amdgpu nvidia-open-dkms nvidia-utils nvidia-prime nvidia-settings"; MODULES="amdgpu";;
    *) echo "${RED}Невірний вибір, встановлюємо mesa${RESET}"; GPU_PKGS="mesa vulkan-radeon vulkan-icd-loader"; MODULES="amdgpu" ;;
esac

# Вибір графічного середовища
echo "${BLUE}=== Виберіть графічне середовище ===${RESET}"
echo "1) Gnome 2) Gnome Minimal 3) KDE 4) KDE Minimal 5) Без графічного середовища"
read -p "${YELLOW}Вибір: ${RESET}" DE
case $DE in
    1) DE_PKGS="gnome gdm pipewire-jack"; DE_SERVICE="gdm" ;;
    2) DE_PKGS="gnome-shell gdm nautilus gnome-control-center gnome-settings-daemon gnome-session xdg-desktop-portal-gnome gvfs gvfs-mtp gnome-keyring gnome-tweaks dconf-editor gnome-terminal gnome-themes-extra gvfs-smb gvfs-nfs pipewire-jack"; DE_SERVICE="gdm" ;;
    3) DE_PKGS="plasma kde-applications sddm"; DE_SERVICE="sddm" ;;
    4) DE_PKGS="plasma-desktop sddm"; DE_SERVICE="sddm" ;;
    5) DE_PKGS=""; DE_SERVICE="" ;;
    *) echo "${RED}Невірний вибір, без графічного середовища${RESET}"; DE_PKGS=""; DE_SERVICE="" ;;
esac

# Встановлення базових пакетів
echo "${YELLOW}Встановлення базових пакетів...${RESET}"
pacstrap -i /mnt base base-devel $KERNEL_PKG linux-firmware $UCODE $FS_TOOLS nano networkmanager $GPU_PKGS $DE_PKGS

# Генерація fstab
echo "${YELLOW}Генерація fstab...${RESET}"
genfstab -U /mnt >> /mnt/etc/fstab

# Вибір локалізації
echo "${BLUE}=== Виберіть мову ===${RESET}"
echo "1) Українська 2) Англійська"
read -p "${YELLOW}Вибір: ${RESET}" LANG
if [ "$LANG" == "1" ]; then
    LOCALE="en_US.UTF-8 UTF-8\nuk_UA.UTF-8 UTF-8"
    LANG_CONF="LANG=uk_UA.UTF-8"
    VCONSOLE="KEYMAP=ua-utf\nFONT=UniCyr_8x16"
else
    LOCALE="en_US.UTF-8 UTF-8"
    LANG_CONF="LANG=en_US.UTF-8"
    VCONSOLE="KEYMAP=us"
fi

# Вибір os-prober
echo "${BLUE}=== Виявлення інших ОС ===${RESET}"
echo "Встановити os-prober? 1) Так 2) Ні"
read -p "${YELLOW}Вибір: ${RESET}" OSPROBER
if [ "$OSPROBER" == "1" ]; then
    OSPROBER_PKG="os-prober"
else
    OSPROBER_PKG=""
fi

# chroot і налаштування
echo "${YELLOW}Налаштування системи в chroot...${RESET}"
arch-chroot /mnt /bin/bash <<EOF
# Часовий пояс
ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime
hwclock --systohc

# Локалізація
echo -e "$LOCALE" > /etc/locale.gen
locale-gen
echo "$LANG_CONF" > /etc/locale.conf
echo -e "$VCONSOLE" > /etc/vconsole.conf

# Ім'я хоста
echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t$HOSTNAME.localdomain $HOSTNAME" > /etc/hosts

# Оптимізація pacman.conf
sed -i '/^#\[multilib\]/,/^#\Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

# Налаштування ядра для GPU
sed -i "s/MODULES=()/MODULES=($MODULES)/" /etc/mkinitcpio.conf
mkinitcpio -P

# Налаштування GRUB
pacman -S --noconfirm grub efibootmgr $OSPROBER_PKG
grub-install --target=x86_64-efi --efi-directory=/boot/efi $DISK
if [ "$OSPROBER" == "1" ]; then
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Гібридна графіка AMD+NVIDIA
if [ "$GPU" == "3" ]; then
    mkdir -p /etc/X11/xorg.conf.d
    echo -e 'Section "OutputClass"\n    Identifier "nvidia"\n    MatchDriver "nvidia-drm"\n    Driver "nvidia"\n    Option "PrimaryGPU" "no"\nEndSection' > /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf
    echo "${GREEN}Переконайтеся, що /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf має правильний вміст:${RESET}"
    cat /etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf
fi

# Паролі та користувач
echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# NetworkManager
systemctl enable NetworkManager

# Додаткові пакети
pacman -S --noconfirm firefox firefox-i18n-uk qbittorrent vlc neofetch btop gnome-browser-connector gnome-tweaks bash-completion adw-gtk-theme steam

# Активація графічного середовища
if [ -n "$DE_SERVICE" ]; then
    systemctl enable $DE_SERVICE
fi

EOF

# Завершення
echo "${GREEN}Встановлення завершено! Розмонтування та перезавантаження...${RESET}"
umount -R /mnt
echo "${YELLOW}Вийміть носій і натисніть Enter для перезавантаження${RESET}"
read
reboot
