# Arch Linux installation guide

## Preparation for installation

### Update the system clock
```bash
timedatectl set-ntp true
```
### Connect to the internet
```bash
rfkill unblock wifi

iw dev waln0 scan | grep SSID

iwctl --passphrase "password" station wlan0 connect "SSID"
```


### Create partitions:
```bash
fdisk -l

fdisk /dev/nvme0n1
```

#### or
```bash
cfdisk /dev/nvme0n1
```

### Format the partitions

#### if **ext4**
```bash
mkfs.vfat -F32 /dev/nvme0n1p1

mkfs.ext4 -L "arch" /dev/nvme0n1p2

mkfs.ext4 -L "home" /dev/nvme0n1p3
```

#### if **f2fs**
```bash
mkfs.f2fs -f -l "arch" /dev/nvme0n1p2

mkfs.f2fs -f -l "home" /dev/nvme0n1p3
```

### Mounting
````bash
mount /dev/nvme0n1p2 /mnt

mkdir -p /mnt/{home,boot/efi}

mount /dev/nvme0n1p3 /mnt/home

mount /dev/nvme0n1p1 /mnt/boot/efi
````

## Installation

### Installing the main packages
```bash
pacstrap -i /mnt base base-devel linux-zen linux-zen-headers linux-firmware amd-ucode networkmanager nano
```
### 
- linux linux-headers
- intel-ucode


## Configure the system

### Generate fstab
```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

### Chroot
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
echo -e "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen

locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

#### If another language:
```bash
echo -e "en_US.UTF-8 UTF-8\nuk_UA.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen

locale-gen

echo "LANG=uk_UA.UTF-8" > /etc/locale.conf

echo -e "KEYMAP=ua-utf\nFONT=UniCyr_8x16" > /etc/vconsole.conf
```

### Hostname
```bash
echo "arch" > /etc/hostname
```

### Bootloader
```bash
pacman -S grub efibootmgr

grub-install /dev/nvme0n1

grub-mkconfig -o /boot/grub/grub.cfg
```

#### If Windows is installed:
```bash
sudo pacman -S os-prober

sudo sed -i '/^#GRUB_DISABLE_OS_PROBER=/ s/^#//' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
```

### User management

#### For root:
```bash
passwd
```

#### Add a new user:
```bash
sudo sed -i '/^# %wheel ALL=(ALL:ALL) ALL/ s/^# //' /etc/sudoers

useradd -m -G wheel -s /bin/bash username

passwd username
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

### Pacman
```bash
sudo sed -i '/^#\[multilib\]/,/^#\Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf

sudo sed -i 's/^ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

sudo sed -i '/^#Color$/ s/^#//' /etc/pacman.conf

sudo pacman -Sy
```

### NVIDIA GPU
```bash
sudo pacman -S nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings 

sudo pacman -S vulkan-icd-loader lib32-vulkan-icd-loader opencl-nvidia lib32-opencl-nvidia cuda libva lib32-libva libva-utils vulkan-tools v4l-utils ffmpeg

printf '%s\n' 'options nvidia NVreg_PreserveVideoMemoryAllocations=1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1' | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

printf '%s\n' 'blacklist i2c_nvidia_gpu' | sudo tee /etc/modprobe.d/nvidia-i2c.conf > /dev/null

printf '%s\n' 'blacklist nouveau' 'options nouveau modeset=0' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null

sudo sed -i '/^MODULES=/ s/)$/nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf

sudo mkinitcpio -P

sudo cat /proc/driver/nvidia/params # for verification of installation
```

### AMD GPU
```bash
sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon

sudo pacman -S vulkan-icd-loader lib32-vulkan-icd-loader libva-mesa-driver lib32-libva-mesa-driver libva lib32-libva libva-utils vulkan-tools v4l-utils ffmpeg mesa-utils lib32-mesa-utils
```

### GNOME
```bash
sudo pacman -S gnome

sudo systemctl enable gdm

sudo reboot
```

### Installation of basic programs
```bash
sudo pacman -S firefox firefox-i18n-uk fastfetch btop nvtop gnome-browser-connector gnome-tweaks bash-completion adw-gtk-theme

paru -S suru-plus-git
```

### Installation paru and pamac
```bash
sudo pacman -S git --needed

git clone https://aur.archlinux.org/paru-bin.git

cd paru-bin && makepkg -sricCf

paru -Syu pamac-aur
```

### Sound and equalizer settings
```bash
sudo pacman -S alsa-utils pipewire pipewire-pulse pipewire-alsa wireplumber easyeffects

sudo pacman -S lsp-plugins lsp-plugins-lv2 lsp-plugins-vst lsp-plugins-vst3 calf mda.lv2 # plugins for equalizer
```

### Installation fonts
```bash
sudo pacman -S noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-ubuntu-font-family ttf-roboto

paru -S ttf-ms-win11-auto
```

### Firewall settings
```bash
sudo pacman -S ufw gufw

sudo systemctl enable --now ufw

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow from 192.168.0.0/24 to any port 5173 proto tcp 

sudo ufw enable
```

### Power profiles
```bash
sudo pacman -S power-profiles-daemon

sudo systemctl enable --now power-profiles-daemon
```

### Game utils
```bash
sudo pacman -S steam

sudo pacman -S gamemode lib32-gamemode mangohud lib32-mangohud goverlay

sudo usermod -aG gamemode $(whoami)

paru -S portproton vkbasalt
```

### Zsh
```bash
sudo pacman -S zsh zsh-completions ttf-firacode-nerd

sudo chsh -s /bin/zsh

sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k

sed -i 's#ZSH_THEME="robbyrussell"#ZSH_THEME="powerlevel10k/powerlevel10k"#' ~/.zshrc

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions)/' ~/.zshrc

printf '%s\n' 'include /usr/share/nano/*.nanorc' >> ~/.nanorc 2>/dev/null
```

#### Fix tty:
```bash
sed -i '/^ZSH_THEME=/c\
if [ "$(tput colors)" -ge 256 ]; then\
  ZSH_THEME="powerlevel10k/powerlevel10k"\
else\
  ZSH_THEME=""\
  PROMPT="%F{green}%n@%m%f %F{yellow}%~%f $ "\
fi' ~/.zshrc
```

### Dnsmasq
```bash
sudo pacman -S dnsmasq

printf '%s\n' '[main]' 'dns=dnsmasq' | sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null

printf '%s\n' 'cache-size=1000' | sudo tee /etc/NetworkManager/dnsmasq.d/cache.conf > /dev/null

nmcli general reload
```

### Cloudlfare WARP
```bash
paru -S cloudflare-warp-bin

sudo systemctl enable --now warp-svc

warp-cli registration new

systemctl --user mask warp-taskbar
```

### Optimization mkinitcpio:
```bash
paru -S mkinitcpio-firmware

printf '%s\n' 'COMPRESSION="lz4"' 'COMPRESSION_OPTIONS=(-9)' | sudo tee -a /etc/mkinitcpio.conf > /dev/null

sudo mkinitcpio -P
```

### Optimization GRUB:
```bash
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*/GRUB_CMDLINE_LINUX_DEFAULT="quiet mitigations=off nmi_watchdog=0 nowatchdog"/' /etc/default/grub

sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Optimization pacman mirrors:
```bash
sudo pacman -S reflector

reflector --protocol https --country Germany,Netherlands --age 6 --sort rate --save /etc/pacman.d/mirrorlist
```

### Change volume step:
```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2
```

### Change switch input shortcut:
```bash
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Shift>Alt_L']"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Alt>Shift_L']"
```

### Optimization fstab:
```bash
ext4   rw,noatime,nodiscard,commit=60,data=ordered
f2fs   rw,noatime,nodiscard,gc_merge,inline_xattr,inline_data,compress_algorithm=zstd
```

### Activation everyweek TRIM:
```bash
sudo systemctl enable --now fstrim.timer
```

### SWAP
#### swapfile:
```bash
sudo fallocate -l 8G /swapfile

sudo chmod 600 /swapfile

sudo mkswap /swapfile

sudo swapon /swapfile

printf '%s\n' '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab > /dev/null

printf '%s\n' 'vm.swappiness=10' 'vm.vfs_cache_pressure=50' | sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null
```

#### zram-generator:
```bash
sudo pacman -S zram-generator

printf '%s\n' '[zram0]' 'zram-size = ram / 2' 'compression-algorithm = lz4' 'swap-priority = 100' | sudo tee /etc/systemd/zram-generator.conf > /dev/null
```

### Headphone front panel activation:
```bash
alsamixer # Line -> 100%

sudo alsactl store

mkdir -p ~/.config/autostart

printf '%s\n' '#!/bin/bash' 'for card in 0 1; do' '    amixer -c $card sset "Headphone" 100% unmute 2>/dev/null || true' '    amixer -c $card sset "Front" 100% unmute 2>/dev/null || true' 'done' > ~/.config/autostart/amixer.sh

chmod +x ~/.config/autostart/amixer.sh

printf '%s\n' '[Desktop Entry]' 'Name=Amixer Headphone Fix' 'Comment=Enable headphone front panel on startup' 'Exec=/home/quinsaiz/.config/autostart/amixer.sh' 'Type=Application' 'Terminal=true' 'Hidden=false' 'StartupNotify=false' 'X-GNOME-Autostart-enabled=true' 'Icon=music' > ~/.config/autostart/amixer.desktop
```

#### amixer.sh:
```bash
!/bin/bash
for card in 0 1; do
    amixer -c $card sset "Headphone" 100% unmute 2>/dev/null || true
    amixer -c $card sset "Front" 100% unmute 2>/dev/null || true
done
```

### Recommended extensions
- [AppIndicator](https://extensions.gnome.org/extension/615/appindicator-support/)
- [BlurMyShell](https://extensions.gnome.org/extension/3193/blur-my-shell/)
- [Dash to Dock](https://extensions.gnome.org/extension/307/dash-to-dock/)
- [Tiling Assistant](https://extensions.gnome.org/extension/3733/tiling-assistant/)
- [System Monitor](https://extensions.gnome.org/extension/6807/system-monitor/)
- [Weather Effect](https://extensions.gnome.org/extension/soon/weather-effect/)

### Hide application .desktop
```bash
NoDisplay=true
```

### For caching new icons:
```bash
sudo gtk-update-icon-cache -f -t /usr/share/icons/"icons_folder"
```

### Cleaning GNOME of unnecessary programs:
```bash
sudo pacman -D --asdeps $(pacman -Qqg gnome)

sudo pacman -D --asexplicit gnome-shell mutter gdm gnome-control-center gnome-console nautilus gnome-session gnome-settings-daemon gnome-backgrounds gvfs gvfs-mtp gnome-text-editor gnome-calculator evince gnome-disk-utility gnome-logs gnome-shell-extensions gnome-system-monitor loupe sushi xdg-desktop-portal-gnome xdg-user-dirs-gtk

sudo pacman -Rsn $(pacman -Qqgdtt gnome)

sudo pacman -Rns $(pacman -Qdtq) # removal unused dependencies
```

### Optimization of processes and rules:
```bash
paru -S ananicy-cpp cachyos-ananicy-rules irqbalance

sudo systemctl enable --now irqbalance ananicy-cpp

sudo mkinitcpio -P
```

### CachyOS repos:
```bash
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz

tar xvf cachyos-repo.tar.xz && cd cachyos-repo

sudo ./cachyos-repo.sh
```