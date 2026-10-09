# Arch Linux installation guide

## Contents

- [Part 1. Installation](#part-1-installation)
- [Part 2. Post-install](#part-2-post-install)
- [Optional](#optional)
- [Quick checks](#quick-checks)

## Part 1. Installation

Everything in this part is run from the live ISO, and after `arch-chroot` inside the new system.

### 1.1 Preparation

#### System clock

```bash
timedatectl set-ntp true
```

#### Wi-Fi

```bash
rfkill unblock wifi
iw dev wlan0 scan | grep SSID
```

```bash
iwctl --passphrase "password" station wlan0 connect "SSID"
```

### 1.2 Partitions

#### Create partitions (interactive)

```bash
fdisk -l
```

```bash
cfdisk /dev/nvme0n1
```

#### EFI partition

Format (new ESP only):

```bash
mkfs.vfat -F32 -n "efi" /dev/nvme0n1p1
```

> Formatting a shared ESP deletes the Windows boot files.
> systemd-boot keeps the kernel and initramfs on the ESP (mounted at `/boot`), so a shared ESP should be at least 512 MB. The one created by the Windows installer is often only about 100 MB.

### 1.3 Filesystem

#### btrfs (default)

Create the subvolumes:

```bash
mkfs.btrfs -L "arch" /dev/nvme0n1p2
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
```

Mount them (`ssd` and `space_cache=v2` are detected or enabled by default, so they are not needed):

```bash
mount -o noatime,compress=zstd:3,subvol=@ /dev/nvme0n1p2 /mnt
mount --mkdir -o noatime,compress=zstd:3,subvol=@home /dev/nvme0n1p2 /mnt/home
mount --mkdir -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
```

---

Optional, only for Snapper: extra subvolumes for logs and the package cache, so that they are not rolled back together with `/`:

```bash
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@pkg
umount /mnt
```

```bash
mount --mkdir -o noatime,compress=zstd:3,subvol=@var_log /dev/nvme0n1p2 /mnt/var/log
mount --mkdir -o noatime,compress=zstd:3,subvol=@pkg /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
```

> Run the second Snapper block after the main mounts above, so that `/mnt` is already mounted.

---

#### ext4 (alternative)

```bash
mkfs.ext4 -L "arch" /dev/nvme0n1p2
mkfs.ext4 -L "home" /dev/nvme0n1p3
mount /dev/nvme0n1p2 /mnt
mount --mkdir /dev/nvme0n1p3 /mnt/home
mount --mkdir -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
```

### 1.4 Base system

```bash
pacstrap /mnt base base-devel \
linux-zen linux-zen-headers \
linux-firmware amd-ucode \
networkmanager nano
```

btrfs only (`base` does not ship the btrfs tools: `btrfs subvolume`, `scrub`, `filesystem usage`):

```bash
pacstrap /mnt btrfs-progs
```

### 1.5 Configure the system

#### Generate fstab and enter the new system

```bash
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
```

#### Time

```bash
ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime
hwclock --systohc
```

> Dual boot: Windows keeps local time in the hardware clock, Linux keeps UTC, so the time jumps after switching systems.
> Fix it on the Windows side (PowerShell as administrator):
>
> ```powershell
> reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_QWORD /f
> ```
>
> Also disable Windows Fast Startup if you mount NTFS partitions from Linux.

#### Localization

```bash
sed -i -E 's/^#\s*((en_US|en_DK|uk_UA)\.UTF-8 UTF-8)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

Optional, Ukrainian system language and console (use instead of the `LANG` line above):

```bash
echo "LANG=uk_UA.UTF-8" > /etc/locale.conf
printf 'KEYMAP=ua-utf\nFONT=UniCyr_8x16\n' > /etc/vconsole.conf
```

#### Hostname

```bash
echo "arch" > /etc/hostname
```

#### Initramfs

Compression (lz4 decompresses faster):

```bash
sed -i 's/^#COMPRESSION="lz4"/COMPRESSION="lz4"/' /etc/mkinitcpio.conf
sed -i 's/^#COMPRESSION_OPTIONS=()/COMPRESSION_OPTIONS=(-9)/' /etc/mkinitcpio.conf
```

btrfs only: remove the `fsck` hook, because `fsck.btrfs` is a stub that does nothing:

```bash
sed -i '/^HOOKS=/ s/ fsck//' /etc/mkinitcpio.conf
```

Build the images once, after all edits:

```bash
mkinitcpio -P
```

#### Users

Root password (interactive):

```bash
passwd
```

Create the user with `sudo` access:

```bash
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
useradd -m -G wheel -s /bin/bash username
```

User password (interactive):

```bash
passwd username
```

#### Bootloader

```bash
bootctl install
systemctl enable systemd-boot-update.service
```

> `bootctl install` copies the EFI binary only once. The `systemd-boot-update` service updates it after `systemd` upgrades.

Loader settings (add `editor no` here after the full system setup):

```bash
tee /boot/loader/loader.conf > /dev/null << 'EOF'
default arch.conf
timeout 5
EOF
```

Boot entry for **btrfs**. `UUID` is the filesystem UUID, and it is the same for every subvolume:

```bash
tee /boot/loader/entries/arch.conf > /dev/null << EOF
title   Arch Linux (Zen)
linux   /vmlinuz-linux-zen
initrd  /amd-ucode.img
initrd  /initramfs-linux-zen.img
options root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) rootflags=subvol=@ rw
EOF
```

Boot entry for **ext4**:

```bash
tee /boot/loader/entries/arch.conf > /dev/null << EOF
title   Arch Linux (Zen)
linux   /vmlinuz-linux-zen
initrd  /amd-ucode.img
initrd  /initramfs-linux-zen.img
options root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) rw
EOF
```

#### NetworkManager

```bash
systemctl enable NetworkManager
```

#### Finish

```bash
exit
umount -R /mnt
reboot
```

## Part 2. Post-install

Log in as the new user. Start with these two steps.

Connect to Wi-Fi (interactive; skip on Ethernet):

```bash
nmtui
```

### 2.1 Pacman and mirrors

Enable `multilib` (needed for Steam and 32-bit libraries), colors and parallel downloads:

```bash
sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf
```

Pick fast mirrors first, then update. This way the big downloads that follow (GNOME, NVIDIA) already use fast mirrors:

```bash
sudo pacman -S --needed reflector && \
sudo reflector --protocol https --country Germany,Ukraine,Poland --age 6 --sort rate --save /etc/pacman.d/mirrorlist && \
sudo pacman -Syu
```

### 2.2 GPU drivers

#### Common utilities (NVIDIA and AMD)

```bash
sudo pacman -S --needed \
vulkan-icd-loader lib32-vulkan-icd-loader \
libva libva-utils vulkan-tools mesa-utils \
v4l-utils ffmpeg
```

#### NVIDIA (default)

Use `nvidia-open` for the stock `linux` kernel and `nvidia-open-dkms` for `linux-zen` and other custom kernels. RTX 50-series cards work only with the open kernel modules.

```bash
sudo pacman -S --needed \
nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
nvidia-settings libva-nvidia-driver
```

Optional: `opencl-nvidia` for OpenCL and `cuda` for CUDA development or ML (several GB):

```bash
sudo pacman -S --needed opencl-nvidia cuda
```

Optional, Turing cards only (RTX 20xx): stop the `i2c_nvidia_gpu` USB-C controller driver from loading and printing errors:

```bash
sudo tee /etc/modprobe.d/nvidia-i2c.conf > /dev/null << 'EOF'
blacklist i2c_nvidia_gpu
EOF
```

> `nvidia_drm modeset=1` and early loading of the NVIDIA modules in the initramfs are not needed: `nvidia-utils` enables modeset by default, and early loading breaks hibernation.
> Verify after the first boot into GNOME, see [Quick checks](#quick-checks).

#### AMD (alternative, or an AMD iGPU)

```bash
sudo pacman -S --needed \
mesa lib32-mesa \
vulkan-radeon lib32-vulkan-radeon
```

### 2.3 GNOME

```bash
sudo pacman -S gnome && \
sudo systemctl enable gdm && \
sudo reboot
```

#### Remove unneeded GNOME apps (optional)

If `pacman` reports `target not found` for a name, delete that name from the list and run it again.

```bash
sudo pacman -Rns \
gnome-calendar gnome-characters gnome-clocks \
gnome-connections gnome-contacts gnome-music \
gnome-font-viewer gnome-maps gnome-software \
gnome-system-monitor gnome-tour gnome-weather \
baobab epiphany simple-scan papers snapshot
```

### 2.4 Programs

#### Basic programs

```bash
sudo pacman -S --needed \
git dosfstools ntfs-3g btop nvtop \
man-db man-pages \
firefox telegram-desktop resources fastfetch luajit \
qbittorrent obs-studio adw-gtk-theme papirus-icon-theme \
gnome-browser-connector gnome-tweaks bash-completion
```

#### Fonts

```bash
sudo pacman -S --needed \
ttf-liberation ttf-roboto ttf-jetbrains-mono-nerd \
noto-fonts noto-fonts-cjk noto-fonts-emoji
```

#### Sound and equalizer

```bash
sudo pacman -S --needed \
pipewire pipewire-pulse pipewire-alsa \
alsa-utils wireplumber easyeffects \
lsp-plugins-lv2 calf
```

DeepFilterNet noise suppression plugin:

```bash
sudo mkdir -p /usr/lib/ladspa && \
sudo curl -L "https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/libdeep_filter_ladspa-0.5.6-x86_64-unknown-linux-gnu.so" -o /usr/lib/ladspa/libdeep_filter_ladspa.so
```

#### Gaming

```bash
sudo pacman -S steam gamemode lib32-gamemode && \
sudo usermod -aG gamemode "$USER"
```

### 2.5 System settings

#### Firewall

```bash
sudo pacman -S --needed ufw gufw && \
sudo systemctl enable --now ufw && \
sudo ufw default deny incoming && \
sudo ufw default allow outgoing && \
sudo ufw enable
```

Allow TCP traffic from the local network (replace `PORT`):

```bash
sudo ufw allow from 192.168.0.0/24 to any port PORT proto tcp
```

#### Power profiles

Mostly useful on laptops:

```bash
sudo pacman -S --needed power-profiles-daemon && \
sudo systemctl enable --now power-profiles-daemon
```

#### Bluetooth

```bash
sudo pacman -S --needed bluez bluez-utils && \
sudo systemctl enable --now bluetooth.service
```

#### Local DNS cache (dnsmasq)

```bash
sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null << 'EOF'
[main]
dns=dnsmasq
EOF
sudo pacman -S --needed dnsmasq && nmcli general reload
```

#### Package cache cleanup

`paccache` keeps the last 3 versions of every package and runs weekly:

```bash
sudo pacman -S --needed pacman-contrib && \
sudo systemctl enable --now paccache.timer
```

#### Swap on zram

```bash
sudo pacman -S --needed zram-generator
```

```bash
sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = lz4
swap-priority = 100
EOF
```

Reboot to activate it (the generator runs at boot).

> `min(ram / 2, 8192)` means half of the RAM, but at most 8 GiB. zram is compressed RAM, so a bigger device only matters under extreme memory pressure, and 8 GiB is plenty on 16 to 32 GB machines.
> `lz4` is faster and uses less CPU than `zstd`, at the cost of a lower compression ratio. This is a good fit for gaming.

Optional tuning for swap on zram (recommended by the Arch Wiki):

```bash
sudo tee /etc/sysctl.d/99-zram.conf > /dev/null << 'EOF'
vm.swappiness=180
vm.page-cluster=0
EOF
```

### 2.6 Shell: zsh

Packages:

```bash
sudo pacman -S --needed zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting
```

Oh My Zsh, Powerlevel10k and the config (non-interactive; `RUNZSH=no CHSH=no` stop the installer from switching shells in the middle of the block):

```bash
RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
sed -i 's#^ZSH_THEME=.*#if [ "$TERM" = "linux" ]; then\n  ZSH_THEME="robbyrussell"\nelse\n  ZSH_THEME="powerlevel10k/powerlevel10k"\nfi#' ~/.zshrc
cat >> ~/.zshrc << 'EOF'

# Plugins (zsh-syntax-highlighting must be sourced last)
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF
```

Nano syntax highlighting:

```bash
echo 'include /usr/share/nano/*.nanorc' >> ~/.nanorc
```

Make zsh the login shell

```bash
chsh -s /bin/zsh
```

Optional, a simpler prompt in the TTY. In `~/.zshrc`, replace the `if [ "$TERM" = "linux" ]; then ... fi` block with:

```bash
if [ "$TERM" = "linux" ]; then
  ZSH_THEME=""
  PROMPT="%F{green}%n@%m%f %F{yellow}%~%f $ "
else
  ZSH_THEME="powerlevel10k/powerlevel10k"
fi
```

### 2.7 AUR

#### paru and pamac

```bash
git clone https://aur.archlinux.org/paru.git /tmp/paru && \
cd /tmp/paru && \
makepkg -si && \
cd ~ && \
rm -rf /tmp/paru
```

```bash
paru -S pamac-aur
```

#### Cloudflare WARP (optional)

```bash
paru -S cloudflare-warp-bin && \
sudo systemctl enable --now warp-svc && \
sleep 2 && \
warp-cli --accept-tos registration new && \
warp-cli connect && \
systemctl --user mask warp-taskbar
```

### 2.8 GNOME settings

Volume step of the media keys:

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2
```

Recommended extensions:

- [AppIndicator](https://extensions.gnome.org/extension/615/appindicator-support/)
- [Blur My Shell](https://extensions.gnome.org/extension/3193/blur-my-shell/)
- [Dash to Dock](https://extensions.gnome.org/extension/307/dash-to-dock/)
- [Tiling Assistant](https://extensions.gnome.org/extension/3733/tiling-assistant/)
- [System Monitor](https://extensions.gnome.org/extension/6807/system-monitor/)
- [Weather Effect](https://extensions.gnome.org/extension/8848/weather-effect/)

## Optional

### Weekly TRIM (ext4)

Not needed on btrfs: modern kernels trim it asynchronously by themselves.

```bash
sudo systemctl enable --now fstrim.timer
```

### Snapper snapshots (btrfs)

Requires the `@var_log` and `@pkg` subvolumes.

```bash
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@pkg
umount /mnt
```

```bash
sudo pacman -S --needed snapper snap-pac
```

Move the snapshots to a dedicated `@snapshots` subvolume:

```bash
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvol=/ /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume create /mnt/btrfs-root/@snapshots
sudo umount /mnt/btrfs-root
sudo rmdir /mnt/btrfs-root
sudo mkdir /.snapshots
sudo mount -o noatime,compress=zstd:3,subvol=@snapshots /dev/nvme0n1p2 /.snapshots
sudo chmod 750 /.snapshots
sudo chown :wheel /.snapshots
echo "UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p2) /.snapshots btrfs noatime,compress=zstd:3,subvol=@snapshots 0 0" | sudo tee -a /etc/fstab > /dev/null
```

Retention (5 hourly, 7 daily) and timers:

```bash
sudo snapper -c root set-config \
"TIMELINE_CREATE=yes" "TIMELINE_CLEANUP=yes" \
"TIMELINE_LIMIT_HOURLY=5" "TIMELINE_LIMIT_DAILY=7" \
"TIMELINE_LIMIT_WEEKLY=0" "TIMELINE_LIMIT_MONTHLY=0" "TIMELINE_LIMIT_YEARLY=0"
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
```

> With systemd-boot the kernel lives on the ESP and is **not** part of a snapshot. After a rollback the old `/usr/lib/modules` no longer matches the running kernel, so reboot into a matching kernel then reinstall `linux-zen` so that the kernel on the ESP matches the modules.
> `genfstab` writes `subvolid=` into `/etc/fstab`. Remove it from the options if you plan to roll back snapshots.

### Swapfile

Not needed with 16 GB or more and zram. It is only useful for hibernation, which also requires the `resume` hook and `resume_offset`, and these are not configured in this guide.

ext4:

```bash
sudo fallocate -l 8G /swapfile && \
sudo chmod 600 /swapfile && \
sudo mkswap /swapfile && \
sudo swapon /swapfile
```

btrfs (creates a swapfile without compression and copy-on-write). With Snapper keep it in its own subvolume, because a subvolume with an active swapfile cannot be snapshotted:

```bash
sudo btrfs filesystem mkswapfile --size 8g /swapfile && \
sudo swapon /swapfile
```

Add it to `fstab`:

```bash
echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab > /dev/null
```

Swap tuning, **without** zram only:

```bash
sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null << 'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
```

## Quick checks

| What | Command | Expected |
| --- | --- | --- |
| NVIDIA params | `sudo cat /proc/driver/nvidia/params` | Configurations related to NVIDIA |
| NVIDIA DRM modeset | `cat /sys/module/nvidia_drm/parameters/modeset` | `Y` |
| Active swap (zram) | `swapon --show` | `/dev/zram0` |
| zswap is not doubling zram | `cat /sys/module/zswap/parameters/enabled` | `N`. If `Y`, add `zswap.enabled=0` to the kernel options (`options` in `arch.conf`, or `GRUB_CMDLINE_LINUX_DEFAULT`) |
| Bootloader | `bootctl status` | systemd-boot is installed, Windows entry is listed |
| Filesystem | `findmnt -no OPTIONS /` | `compress=zstd:3` and `subvol=/@` (btrfs) |
| Time sync | `timedatectl` | `System clock synchronized: yes` |
