# Arch Linux installation guide

## Preparation for installation

### Update the system clock

```bash
timedatectl set-ntp true
```

### Connect to the internet (Wi-Fi)

```bash
rfkill unblock wifi

iw dev wlan0 scan | grep SSID

iwctl --passphrase "password" station wlan0 connect "SSID"
```

### Create partitions

```bash
fdisk -l

cfdisk /dev/nvme0n1
```

#### Create EFI partition

```bash
mkfs.vfat -F32 -n "EFI" /dev/nvme0n1p1
```

---

### EXT4

#### Create main partition

```bash
mkfs.ext4 -L "arch" /dev/nvme0n1p2

mkfs.ext4 -L "home" /dev/nvme0n1p3
```

#### Mount

````bash
mount /dev/nvme0n1p2 /mnt

mount --mkdir /dev/nvme0n1p3 /mnt/home

mount --mkdir -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
````

---

### BTRFS

#### Create subvolumes partition

```bash
mkfs.btrfs -L "arch" /dev/nvme0n1p2

mount /dev/nvme0n1p2 /mnt

btrfs subvolume create /mnt/@

btrfs subvolume create /mnt/@home

# for Snapper
btrfs subvolume create /mnt/@var_log

btrfs subvolume create /mnt/@pkg
#

umount /mnt
```

#### Mount subvolumes

```bash
mount -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@ /dev/nvme0n1p2 /mnt

mount --mkdir -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@home /dev/nvme0n1p2 /mnt/home

# for Snapper
mount --mkdir -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@var_log /dev/nvme0n1p2 /mnt/var/log

mount --mkdir -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@pkg /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
#

mount --mkdir -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
```

## Installation

### Installing the main packages

```bash
pacstrap /mnt base base-devel \
linux-zen linux-zen-headers \
linux-firmware amd-ucode \
networkmanager nano
```

## Configure the system

### Generate fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

### Arch Chroot

```bash
arch-chroot /mnt
```

### Time

```bash
ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime

hwclock --systohc
```

### Localization

```bash
sed -i \
's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
/etc/locale.gen

locale-gen

echo \
"LANG=en_US.UTF-8" \
> /etc/locale.conf
```

#### If another language

```bash
sed -i \
's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
/etc/locale.gen

sed -i \
's/#uk_UA.UTF-8 UTF-8/uk_UA.UTF-8 UTF-8/' \
/etc/locale.gen

locale-gen

echo \
"LANG=uk_UA.UTF-8" \
> /etc/locale.conf

echo -e \
"KEYMAP=ua-utf\nFONT=UniCyr_8x16" \
> /etc/vconsole.conf
```

### Hostname

```bash
echo \
"arch" \
> /etc/hostname
```

### Bootloader

#### systemd-boot

```bash
bootctl install

# add 'editor no' here after full system setup
printf '%s\n' \
'default arch.conf' \
'timeout 5' \
| tee /boot/loader/loader.conf > /dev/null

# UUID refers to Filesystem UUID
# if btrfs before rw should be 'rootflags=subvol=@'
printf '%s\n' \
'title   Arch Linux (Zen)' \
'linux   /vmlinuz-linux-zen' \
'initrd  /amd-ucode.img' \
'initrd  /initramfs-linux-zen.img' \
"options root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) rw" \
| tee /boot/loader/entries/arch.conf > /dev/null
```

#### grub

```bash
pacman -S grub efibootmgr

grub-install /dev/nvme0n1

grub-mkconfig -o /boot/grub/grub.cfg
```

#### If Windows is installed (only with grub)

```bash
pacman -S os-prober

sed -i \
'/^#GRUB_DISABLE_OS_PROBER=/ s/^#//' \
/etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
```

### User management

#### Set password for root

```bash
passwd
```

#### Add a new user

```bash
sed -i \
'/^# %wheel ALL=(ALL:ALL) ALL/ s/^# //' \
/etc/sudoers

useradd -m -G wheel -s /bin/bash username

passwd username
```

### Remove fsck from HOOKS (for btrfs)
```bash
sed -i \
's/\bfsck\b//g; s/  */ /g; s/( /(/' \
/etc/mkinitcpio.conf

mkinitcpio -P
```

### NetworkManager activation

```bash
systemctl enable NetworkManager
```

### End of installation

```bash
exit

umount -R /mnt

reboot
```

## Post-install

### Connect to the Wi-Fi

```bash
nmtui
```

### Pacman

```bash
sudo sed -i \
'/^#\[multilib\]/,/^#\Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' \
/etc/pacman.conf

sudo sed -i \
's/^ParallelDownloads = 5/ParallelDownloads = 10/' \
/etc/pacman.conf

sudo sed -i \
'/^#Color$/ s/^#//' \
/etc/pacman.conf

sudo pacman -Syu
```

### NVIDIA GPU

```bash
# use 'nvidia-open' for stock linux kernel, 'nvidia-open-dkms' for custom kernels
sudo pacman -S \
nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
nvidia-settings --needed 

sudo pacman -S \
vulkan-icd-loader lib32-vulkan-icd-loader \
opencl-nvidia libva libva-utils libva-nvidia-driver \
vulkan-tools mesa-utils v4l-utils ffmpeg cuda --needed

printf '%s\n' \
'options nvidia_drm modeset=1' \
| sudo tee /etc/modprobe.d/nvidia-drm.conf > /dev/null

printf '%s\n' \
'blacklist i2c_nvidia_gpu' \
| sudo tee /etc/modprobe.d/nvidia-i2c.conf > /dev/null

sudo sed -i \
's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
/etc/mkinitcpio.conf

sudo mkinitcpio -P

# for verification of installation
sudo cat /proc/driver/nvidia/params
```

### AMD GPU

```bash
sudo pacman -S \
mesa lib32-mesa \
vulkan-radeon lib32-vulkan-radeon \
--needed

sudo pacman -S \
vulkan-icd-loader lib32-vulkan-icd-loader \
libva-mesa-driver lib32-libva-mesa-driver \
libva libva-utils vulkan-tools mesa-utils \
v4l-utils ffmpeg --needed
```

### GNOME

```bash
sudo pacman -S gnome

sudo systemctl enable gdm

sudo reboot
```

### Installation of basic programs

```bash
sudo pacman -S \
git dosfstools ntfs-3g btop nvtop \
firefox telegram-desktop resources fastfetch luajit \
qbittorrent obs-studio adw-gtk-theme papirus-icon-theme \
gnome-browser-connector gnome-tweaks bash-completion --needed
```

### Sound and equalizer settings

```bash
sudo pacman -S \
pipewire pipewire-pulse pipewire-alsa \
alsa-utils wireplumber easyeffects --needed

sudo pacman -S lsp-plugins-lv2 calf

sudo curl -L \
"https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/libdeep_filter_ladspa-0.5.6-x86_64-unknown-linux-gnu.so" \
-o /usr/lib/ladspa/libdeep_filter_ladspa.so
```

### Installation fonts

```bash
sudo pacman -S \
ttf-liberation ttf-roboto ttf-jetbrains-mono-nerd \
noto-fonts noto-fonts-cjk noto-fonts-emoji --needed
```

### Firewall settings

```bash
sudo pacman -S ufw gufw && \
sudo systemctl enable --now ufw && \
sudo ufw default deny incoming && \
sudo ufw default allow outgoing && \
sudo ufw enable

# allow TCP traffic from local network
sudo ufw allow from 192.168.0.0/24 to any port "PORT" proto tcp 
```

### Power profiles

```bash
sudo pacman -S power-profiles-daemon && \
sudo systemctl enable --now power-profiles-daemon
```

### Gaming utils

```bash
sudo pacman -S steam

sudo pacman -S gamemode lib32-gamemode && \
sudo usermod -aG gamemode $(whoami)
```

### zsh

```bash
sudo pacman -S zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting

chsh -s /bin/zsh

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k

sed -i \
's#ZSH_THEME="robbyrussell"#if [ "$TERM" = "linux" ]; then\n  ZSH_THEME="robbyrussell"\nelse\n  ZSH_THEME="powerlevel10k/powerlevel10k"\nfi#' \
~/.zshrc

printf '%s\n' \
"" \
'# Plugins' \
'source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
'source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' \
>> ~/.zshrc

printf '%s\n' \
'include /usr/share/nano/*.nanorc' \
>> ~/.nanorc

sudo chsh -s /bin/bash root
```

#### for better tty zsh style
```bash
if [ "$TERM" = "linux" ]; then
  ZSH_THEME=""
  PROMPT="%F{green}%n@%m%f %F{yellow}%~%f $ "
else
  ZSH_THEME="powerlevel10k/powerlevel10k"
fi
```

### Dnsmasq

```bash
sudo pacman -S dnsmasq

printf '%s\n' \
'[main]' \
'dns=dnsmasq' \
| sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null

nmcli general reload
```

### Optimization mkinitcpio

```bash
sudo sed -i \
's/^#COMPRESSION="lz4"/COMPRESSION="lz4"/' \
/etc/mkinitcpio.conf

sudo sed -i \
's/^#COMPRESSION_OPTIONS=()/COMPRESSION_OPTIONS=(-9)/' \
/etc/mkinitcpio.conf

sudo mkinitcpio -P
```

### Activation everyweek TRIM (for EXT4)

```bash
sudo systemctl enable --now fstrim.timer
```

### Snapper

```bash
sudo pacman -S snapper snap-pac

sudo snapper -c root create-config /

sudo btrfs subvolume delete /.snapshots

sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvol=/ /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume create /mnt/btrfs-root/@snapshots
sudo umount /mnt/btrfs-root
sudo rmdir /mnt/btrfs-root

sudo mkdir /.snapshots
sudo mount -o noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@snapshots /dev/nvme0n1p2 /.snapshots

sudo chmod 750 /.snapshots
sudo chown :wheel /.snapshots

echo "UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) /.snapshots btrfs noatime,compress=zstd:3,ssd,space_cache=v2,subvol=@snapshots 0 0" | sudo tee -a /etc/fstab > /dev/null

sudo snapper -c root set-config \
"TIMELINE_CREATE=yes" \
"TIMELINE_CLEANUP=yes" \
"TIMELINE_LIMIT_HOURLY=5" \
"TIMELINE_LIMIT_DAILY=7" \
"TIMELINE_LIMIT_WEEKLY=0" \
"TIMELINE_LIMIT_MONTHLY=0" \
"TIMELINE_LIMIT_YEARLY=0"

sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
```

### Extented configure locales

```bash
sudo sed -i -E 's/#\s*((en_DK|uk_UA).UTF-8 UTF-8)/\1/' /etc/locale.gen

printf '%s\n' \
'LANG=en_US.UTF-8' \
'LC_TIME=en_DK.UTF-8' \
'LC_MONETARY=uk_UA.UTF-8' \
'LC_NUMERIC=uk_UA.UTF-8' \
'LC_MEASUREMENT=uk_UA.UTF-8' \
'LC_PAPER=uk_UA.UTF-8' \
| sudo tee /etc/locale.conf > /dev/null
```

### Optimization pacman mirrors

```bash
sudo pacman -S reflector

sudo reflector \
--protocol https \
--country Germany,Ukraine,Poland \
--age 6 \
--sort rate \
--save /etc/pacman.d/mirrorlist

sudo pacman -Syyu
```

### Installation paru and pamac

```bash
git clone https://aur.archlinux.org/paru.git && \
cd paru && makepkg -si

paru -S pamac-aur
```

### Bluetooth

```bash
sudo pacman -S bluez bluez-utils --needed

sudo systemctl enable --now bluetooth.service
```

### Cloudlfare WARP

```bash
paru -S cloudflare-warp-bin

sudo systemctl enable --now warp-svc

warp-cli registration new

systemctl --user mask warp-taskbar
```

### SWAP

#### zram-generator

```bash
sudo pacman -S zram-generator

printf '%s\n' \
'[zram0]' \
'zram-size = ram / 2' \
'compression-algorithm = lz4' \
'swap-priority = 100' \
| sudo tee /etc/systemd/zram-generator.conf > /dev/null
```

#### swapfile

```bash
# if ext4
sudo fallocate -l 8G /swapfile && \
sudo chmod 600 /swapfile && \
sudo mkswap /swapfile && \
sudo swapon /swapfile

# if btrfs
sudo truncate -s 0 /swapfile && \
sudo chattr +C /swapfile && \
sudo fallocate -l 8G /swapfile && \
sudo chmod 600 /swapfile && \
sudo mkswap /swapfile && \
sudo swapon /swapfile

printf '%s\n' \
'/swapfile none swap defaults 0 0' \
| sudo tee -a /etc/fstab > /dev/null

printf '%s\n' \
'vm.swappiness=10' \
'vm.vfs_cache_pressure=50' \
| sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null
```

### Change volume step

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2
```

### Recommended extensions

- [AppIndicator](https://extensions.gnome.org/extension/615/appindicator-support/)
- [BlurMyShell](https://extensions.gnome.org/extension/3193/blur-my-shell/)
- [Dash to Dock](https://extensions.gnome.org/extension/307/dash-to-dock/)
- [Tiling Assistant](https://extensions.gnome.org/extension/3733/tiling-assistant/)
- [System Monitor](https://extensions.gnome.org/extension/6807/system-monitor/)
- [Weather Effect](https://extensions.gnome.org/extension/8848/weather-effect/)

### Fix suspend on amdgpu

#### if systemd-boot

```bash
sudo sed -i \
'/^options/ s/$/ amdgpu.runpm=0/' \
/boot/loader/entries/arch.conf
```

#### if grub

```bash
sudo sed -i \
's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 amdgpu.runpm=0"/' \
/etc/default/grub

sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### For caching new icons

```bash
sudo gtk-update-icon-cache -f -t /usr/share/icons/*
```

### Remove standart GNOME apps

```bash
sudo pacman -Rns \
gnome-calendar gnome-characters gnome-clocks \
gnome-connections gnome-contacts gnome-music \
gnome-font-viewer gnome-maps gnome-software \
gnome-system-monitor gnome-tour gnome-weather \
baobab epiphany simple-scan papers snapshot
```

### Cleaning GNOME of unnecessary programs (Be careful)

```bash
sudo pacman -D --asdeps $(pacman -Qqg gnome)

sudo pacman -D --asexplicit \
gnome-shell mutter gdm gnome-control-center \
gnome-console nautilus gnome-session \
gnome-settings-daemon gnome-backgrounds \
gvfs gvfs-mtp gnome-text-editor gnome-calculator \
evince gnome-disk-utility gnome-logs \
gnome-shell-extensions gnome-system-monitor \
loupe sushi xdg-desktop-portal-gnome \
xdg-user-dirs-gtk

sudo pacman -Rsn $(pacman -Qqgdtt gnome)

# removal unused dependencies
sudo pacman -Rns $(pacman -Qdtq)
```

### Headphone front panel activation

```bash
alsamixer # Line -> 100%

sudo alsactl store

mkdir -p ~/.config/autostart

cat << 'EOF' > ~/.config/autostart/amixer.sh
#!/bin/bash
for card in 0 1; do
    amixer -c $card sset "Headphone" 100% unmute 2>/dev/null || true
    amixer -c $card sset "Front" 100% unmute 2>/dev/null || true
done
EOF

chmod +x ~/.config/autostart/amixer.sh

cat << 'EOF' > ~/.config/autostart/amixer.desktop
[Desktop Entry]
Name=Amixer Headphone Fix
Comment=Enable headphone front panel on startup
Exec=/bin/bash -c "~/.config/autostart/amixer.sh"
Type=Application
Terminal=true
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
Icon=music
EOF
```
