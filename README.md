# Arch Linux Installation & Setup Guide

Step-by-step guide for installing and configuring **Arch Linux** (UEFI, `systemd-boot`, `btrfs` or `ext4`).

## Contents

- [Quick Start with the Script](#quick-start-with-the-script)
- [Part 1. Base System Installation (Live ISO)](#part-1-base-system-installation-live-iso)
  - [1.1 Preparation and Network](#11-preparation-and-network)
  - [1.2 Disk Partitioning](#12-disk-partitioning)
  - [1.3 Filesystem and Mounting](#13-filesystem-and-mounting)
  - [1.4 Base System Packages](#14-base-system-packages)
  - [1.5 Configuration Inside arch-chroot](#15-configuration-inside-arch-chroot)
- [Part 2. Post-install Setup](#part-2-post-install-setup)
  - [2.1 Pacman and Mirrors](#21-pacman-and-mirrors)
  - [2.2 GPU Drivers](#22-gpu-drivers)
  - [2.3 Desktop Environment (DE)](#23-desktop-environment-de)
  - [2.4 Applications, Fonts, Audio, and Gaming](#24-applications-fonts-audio-and-gaming)
  - [2.5 System Services and zram](#25-system-services-and-zram)
  - [2.6 Shell: Zsh + Starship](#26-shell-zsh--starship)
  - [2.7 AUR (paru, pamac, WARP)](#27-aur-paru-pamac-warp)
  - [2.8 Final DE and Security Settings](#28-final-de-and-security-settings)
- [Optional Settings (Manual)](#optional-settings-manual)
- [Quick System Checks](#quick-system-checks)

## Quick Start with the Script

When using `arch-setup.sh`, the script automatically detects the environment (Live ISO or installed system), or accepts an explicit mode:

| Command | Environment | Description |
| --- | --- | --- |
| `./arch-setup.sh` | Auto | Runs `install` on the Live ISO or `post` on an installed system |
| `./arch-setup.sh install` | Live ISO (`root`) | Partitioning (`cfdisk`), formatting, `pacstrap`, `fstab`, `chroot`, `systemd-boot` |
| `./arch-setup.sh post` | User | GPU drivers, KDE/GNOME, apps, `ufw`, `zram`, `zsh + starship`, Snapper |
| `./arch-setup.sh shell` | User | Installs and configures `zsh + starship` only |
| `./arch-setup.sh check` | User | Verifies GPU, `zram`, `zswap`, `systemd-boot`, services, KDE shortcut duplicates, and KWallet |

> **Note:** Disk partitioning (`cfdisk`), connecting to Wi-Fi on the Live ISO, and the `i2c_nvidia_gpu` fix are intentionally manual steps.

## Part 1. Base System Installation (Live ISO)

Everything in this section is run from the **Arch Linux Live ISO**, and after `arch-chroot` inside the new system.

### 1.1 Preparation and Network

#### Synchronize System Clock

```bash
timedatectl set-ntp true
```

#### Connect to Wi-Fi (skip on Ethernet)

```bash
rfkill unblock wifi
iw dev wlan0 scan | grep SSID
iwctl --passphrase "password" station wlan0 connect "SSID"
```

### 1.2 Disk Partitioning

Inspect available drives and create partitions interactively:

```bash
cfdisk /dev/nvme0n1
```

Format **only a newly created** ESP:

```bash
mkfs.vfat -F32 -n EFI /dev/nvme0n1p1
```

### 1.3 Filesystem and Mounting

#### Option A: btrfs (default)

Create the base subvolumes:

```bash
mkfs.btrfs -f -L arch /dev/nvme0n1p2
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
```

Mount the subvolumes (`ssd` and `space_cache=v2` are enabled automatically by modern kernels):

```bash
mount -o noatime,compress=zstd:3,subvol=@ /dev/nvme0n1p2 /mnt
mount --mkdir -o noatime,compress=zstd:3,subvol=@home /dev/nvme0n1p2 /mnt/home
mount --mkdir -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
```

<details>
<summary>Optional: Extra subvolumes for Snapper (<code>@var_log</code>, <code>@pkg</code>)</summary>

Prevents system logs and the package cache from being rolled back together with `/`:

```bash
mount /dev/nvme0n1p2 /mnt
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@pkg
umount /mnt

mount --mkdir -o noatime,compress=zstd:3,subvol=@var_log /dev/nvme0n1p2 /mnt/var/log
mount --mkdir -o noatime,compress=zstd:3,subvol=@pkg /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
```

</details>

#### Option B: ext4 (alternative)

```bash
mkfs.ext4 -F -L "arch" /dev/nvme0n1p2
mkfs.ext4 -F -L "home" /dev/nvme0n1p3

mount /dev/nvme0n1p2 /mnt
mount --mkdir /dev/nvme0n1p3 /mnt/home
mount --mkdir -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
```

### 1.4 Base System Packages

Replace `amd-ucode` with `intel-ucode` for Intel CPUs, and `linux-zen` with `linux` if preferred:

```bash
pacstrap -K /mnt base base-devel \
  linux-zen linux-zen-headers \
  linux-firmware amd-ucode \
  networkmanager nano
```

For **btrfs** only (`base` does not ship btrfs management tools):

```bash
pacstrap /mnt btrfs-progs
```

### 1.5 Configuration Inside arch-chroot

#### Generate `fstab` and Enter the New System

```bash
genfstab -U /mnt > /mnt/etc/fstab
```

For **btrfs**, strip `subvolid=` so snapshot rollbacks work cleanly:

```bash
sed -i -E 's/subvolid=[0-9]+,//g' /mnt/etc/fstab
```

Enter the new system:

```bash
arch-chroot /mnt
```

#### Time Zone

```bash
ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime
hwclock --systohc
```

> **Dual boot with Windows:** Windows stores local time in the hardware clock (RTC), whereas Linux uses UTC. To prevent clock drift when switching OSes, run this in an administrator PowerShell on Windows:
>
> ```powershell
> reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_QWORD /f
> ```
>
> Also disable Windows **Fast Startup** if you mount NTFS partitions from Linux.

#### Localization and Regional Formats

English system language (`en_US`), ISO dates and 24-hour time (`en_DK`), and Ukrainian formats for numbers, currency, measurement units, and paper size (`uk_UA`):

```bash
sed -i -E 's/^#\s*((en_US|en_DK|uk_UA)\.UTF-8 UTF-8)/\1/' /etc/locale.gen
locale-gen

cat > /etc/locale.conf << 'EOF'
LANG=en_US.UTF-8
LC_TIME=en_DK.UTF-8
LC_MONETARY=uk_UA.UTF-8
LC_NUMERIC=uk_UA.UTF-8
LC_MEASUREMENT=uk_UA.UTF-8
LC_PAPER=uk_UA.UTF-8
EOF
```

<details>
<summary>Optional: Full Ukrainian system interface and TTY console</summary>

```bash
echo "LANG=uk_UA.UTF-8" > /etc/locale.conf
printf 'KEYMAP=ua-utf\nFONT=UniCyr_8x16\n' > /etc/vconsole.conf
```

</details>

#### Hostname

```bash
echo "arch" > /etc/hostname
```

#### Initramfs (`mkinitcpio`)

Enable fast `lz4` decompression:

```bash
cat >> /etc/mkinitcpio.conf << 'EOF'

COMPRESSION="lz4"
COMPRESSION_OPTIONS=(-9)
EOF
```

For **btrfs** only — remove the `fsck` hook (`fsck.btrfs` is a no-op stub):

```bash
sed -i '/^HOOKS=/ s/ fsck//' /etc/mkinitcpio.conf
```

Build the initramfs images:

```bash
mkinitcpio -P
```

#### Users and `sudo` Access

```bash
passwd
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
useradd -m -G wheel -s /bin/bash username
passwd username
```

#### Bootloader (`systemd-boot`)

```bash
bootctl install
systemctl enable systemd-boot-update.service

tee /boot/loader/loader.conf > /dev/null << 'EOF'
default arch.conf
timeout 5
EOF
```

Boot entry for **btrfs** (`zswap.enabled=0` disables zswap upfront in favor of zram):

```bash
tee /boot/loader/entries/arch.conf > /dev/null << EOF
title   Arch Linux
linux   /vmlinuz-linux-zen
initrd  /amd-ucode.img
initrd  /initramfs-linux-zen.img
options root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) rootflags=subvol=@ rw zswap.enabled=0
EOF
```

For **ext4** boot entry remove `rootflags=subvol=@`:

#### Enable Services and Reboot

```bash
systemctl enable NetworkManager.service
systemctl enable systemd-timesyncd.service
exit
umount -R /mnt
reboot
```

## Part 2. Post-install Setup

Log in as your newly created user. If using Wi-Fi, connect via `nmtui`.

### 2.1 Pacman and Mirrors

Enable `multilib`, colored output, and parallel downloads:

```bash
sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf
```

Refresh mirrors for speed and update the system:

```bash
sudo pacman -S --needed reflector && \
sudo reflector --protocol https --country Germany,Ukraine,Poland --age 6 --sort rate --save /etc/pacman.d/mirrorlist && \
sudo pacman -Syu
```

### 2.2 GPU Drivers

#### Common Utilities (all GPUs)

```bash
sudo pacman -S --needed \
  vulkan-icd-loader lib32-vulkan-icd-loader \
  libva libva-utils vulkan-tools mesa-utils v4l-utils
```

#### NVIDIA (default)

Use `nvidia-open` for the stock `linux` kernel, and `nvidia-open-dkms` for `linux-zen` or other custom kernels. RTX 50-series GPUs work exclusively with the open kernel modules.

```bash
sudo pacman -S --needed \
  nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
  nvidia-settings libva-nvidia-driver
```

- **Optional (OpenCL / CUDA, requires several GB):**

  ```bash
  sudo pacman -S --needed opencl-nvidia cuda
  ```

- **Optional (Turing / RTX 20xx GPUs only):** Prevents `i2c_nvidia_gpu` USB-C controller errors during boot:

  ```bash
  sudo tee /etc/modprobe.d/nvidia-i2c.conf > /dev/null << 'EOF'
  blacklist i2c_nvidia_gpu
  EOF
  ```

> **NVIDIA Notes:**
>
> - Manually setting `nvidia_drm.modeset=1` or adding NVIDIA modules to `initramfs` is not required: `nvidia-utils` enables modeset by default, and early module loading breaks hibernation.
> - With driver 595+ (open modules), `UseKernelSuspendNotifiers` handles VRAM preservation automatically during sleep, so `nvidia-suspend`, `nvidia-resume`, and `nvidia-hibernate` services should remain disabled.

#### AMD / Intel (alternative)

```bash
# AMD
sudo pacman -S --needed mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon

# Intel
sudo pacman -S --needed mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver
```

### 2.3 Desktop Environment (DE)

#### Option A: KDE Plasma

```bash
sudo pacman -S --needed \
  plasma-desktop plasma-login-manager \
  plasma-nm plasma-pa powerdevil kscreen qt6-tools \
  kde-gtk-config breeze-gtk xdg-desktop-portal-kde \
  plasma-firewall tesseract-data-eng tesseract-data-ukr \
  plasma-browser-integration plasma-systemmonitor \
  kinfocenter kwallet kwallet-pam kwalletmanager && \
sudo systemctl enable plasmalogin.service
```

Essential KDE applications:

```bash
sudo pacman -S --needed \
  konsole dolphin kio-admin spectacle gwenview \
  vlc vlc-plugin-ffmpeg kate ark kalk
```

> **KWallet Setup:** After your first login to KDE, open `kwalletmanager` and create a wallet named `kdewallet` using **Blowfish** encryption (not GPG) and **the exact same password as your user login** so `kwallet-pam` unlocks it automatically.

#### Option B: GNOME

```bash
sudo pacman -S gnome && \
sudo systemctl enable gdm.service
```

Remove unneeded default GNOME apps (optional):

```bash
sudo pacman -Rns \
  gnome-calendar gnome-characters gnome-clocks \
  gnome-connections gnome-contacts gnome-music \
  gnome-font-viewer gnome-maps gnome-software \
  gnome-system-monitor gnome-tour gnome-weather \
  baobab epiphany simple-scan papers snapshot
```

### 2.4 Applications, Fonts, Audio, and Gaming

#### Core Utilities and Applications

```bash
sudo pacman -S --needed \
  dosfstools ntfs-3g btop nvtop fastfetch ffmpeg \
  git firefox telegram-desktop obs-studio luajit \
  qbittorrent papirus-icon-theme bash-completion
```

GNOME-specific additions:

```bash
sudo pacman -S --needed resources adw-gtk-theme gnome-browser-connector gnome-tweaks
```

#### Fonts

```bash
sudo pacman -S --needed \
  ttf-liberation ttf-roboto ttf-jetbrains-mono-nerd \
  noto-fonts noto-fonts-cjk noto-fonts-emoji
```

#### Audio and Equalizer (PipeWire + EasyEffects)

```bash
sudo pacman -S --needed \
  pipewire pipewire-pulse pipewire-alsa pipewire-jack \
  alsa-utils wireplumber easyeffects lsp-plugins-lv2 calf
```

Optional — **DeepFilterNet** noise suppression LADSPA plugin:

```bash
sudo mkdir -p /usr/lib/ladspa && \
sudo curl -L "https://github.com/Rikorose/DeepFilterNet/releases/download/v0.5.6/libdeep_filter_ladspa-0.5.6-x86_64-unknown-linux-gnu.so" -o /usr/lib/ladspa/libdeep_filter_ladspa.so
```

#### Gaming

```bash
sudo pacman -S --needed steam gamemode lib32-gamemode && \
sudo usermod -aG gamemode "$USER"
```

### 2.5 System Services and zram

#### Firewall (`ufw`)

```bash
sudo pacman -S --needed ufw && \
sudo systemctl enable --now ufw.service && \
sudo ufw default deny incoming && \
sudo ufw default allow outgoing && \
sudo ufw logging off && \
sudo ufw --force enable
```

Optional — allow local TCP traffic (replace `PORT`):

```bash
sudo ufw allow from 192.168.0.0/24 to any port PORT proto tcp
```

#### Power Profiles, Bluetooth, DNS Cache, and Package Cleanup

```bash
# Power profiles
sudo pacman -S --needed power-profiles-daemon && \
sudo systemctl enable --now power-profiles-daemon.service

# Bluetooth (also install bluedevil on KDE)
sudo pacman -S --needed bluez bluez-utils bluedevil && \
sudo systemctl enable --now bluetooth.service

# Local DNS cache via dnsmasq
sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null << 'EOF'
[main]
dns=dnsmasq
EOF
sudo pacman -S --needed dnsmasq && sudo nmcli general reload

# Weekly pacman cache cleanup (keeps the last 3 versions)
sudo pacman -S --needed pacman-contrib && \
sudo systemctl enable --now paccache.timer
```

#### Swap on zram

```bash
sudo pacman -S --needed zram-generator

sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = lz4
swap-priority = 100
EOF

sudo tee /etc/sysctl.d/99-zram.conf > /dev/null << 'EOF'
vm.swappiness=180
vm.page-cluster=0
EOF
```

> Verify that `zswap.enabled=0` is present in the `options` line of `/boot/loader/entries/arch.conf` so pages are not compressed twice.

### 2.6 Shell: Zsh + Starship

Install packages and generate the Starship preset (`gruvbox-rainbow`):

```bash
sudo pacman -S --needed zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting starship
mkdir -p ~/.config
starship preset gruvbox-rainbow -o ~/.config/starship.toml
```

Configure `~/.zshrc` (with `terminfo`-based key bindings, plain prompt fallback for Linux TTY, and system plugins):

```bash
cat > ~/.zshrc << 'EOF'
# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS SHARE_HISTORY

# --- Options ---
setopt AUTO_CD INTERACTIVE_COMMENTS

# --- Completion ---
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# --- Key bindings (terminfo based) ---
bindkey -e
zmodload zsh/terminfo
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search

typeset -gA key
key=(
  Home      "${terminfo[khome]}"
  End       "${terminfo[kend]}"
  Delete    "${terminfo[kdch1]}"
  Up        "${terminfo[kcuu1]}"
  Down      "${terminfo[kcud1]}"
  CtrlLeft  "${terminfo[kLFT5]}"
  CtrlRight "${terminfo[kRIT5]}"
)
[[ -n ${key[Home]} ]] && bindkey -- "${key[Home]}" beginning-of-line
[[ -n ${key[End]} ]] && bindkey -- "${key[End]}" end-of-line
[[ -n ${key[Delete]} ]] && bindkey -- "${key[Delete]}" delete-char
[[ -n ${key[Up]} ]] && bindkey -- "${key[Up]}" up-line-or-beginning-search
[[ -n ${key[Down]} ]] && bindkey -- "${key[Down]}" down-line-or-beginning-search
[[ -n ${key[CtrlLeft]} ]] && bindkey -- "${key[CtrlLeft]}" backward-word
[[ -n ${key[CtrlRight]} ]] && bindkey -- "${key[CtrlRight]}" forward-word

if (( ${+terminfo[smkx]} && ${+terminfo[rmkx]} )); then
  autoload -Uz add-zle-hook-widget
  zle_application_mode_start() { echoti smkx }
  zle_application_mode_stop() { echoti rmkx }
  add-zle-hook-widget -Uz zle-line-init zle_application_mode_start
  add-zle-hook-widget -Uz zle-line-finish zle_application_mode_stop
fi

# --- Prompt: plain prompt in Linux TTY, starship elsewhere ---
if [[ $TERM == linux ]] || ! (( ${+commands[starship]} )); then
  PROMPT='%F{green}%n@%m%f %F{yellow}%~%f %# '
else
  eval "$(starship init zsh)"
fi

# --- Plugins ---
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF
```

Enable syntax highlighting in `nano` and set `zsh` as your login shell:

```bash
echo 'include /usr/share/nano/*.nanorc' >> ~/.nanorc
chsh -s /usr/bin/zsh
```

### 2.7 AUR (paru, pamac, WARP)

#### Install `paru` and `pamac-aur`

```bash
git clone https://aur.archlinux.org/paru.git /tmp/paru && \
cd /tmp/paru && \
makepkg -si && \
cd ~ && \
rm -rf /tmp/paru

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

### 2.8 Final DE and Security Settings

#### Harden the Boot Menu (`systemd-boot`)

Disable editing kernel parameters at boot after setup is complete:

```bash
echo 'editor no' | sudo tee -a /boot/loader/loader.conf > /dev/null
```

#### GNOME Defaults and Extensions

Set media key volume step to 2%:

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 2
```

Recommended GNOME extensions:

- [AppIndicator](https://extensions.gnome.org/extension/615/appindicator-support/)
- [Blur My Shell](https://extensions.gnome.org/extension/3193/blur-my-shell/)
- [Dash to Dock](https://extensions.gnome.org/extension/307/dash-to-dock/)
- [Tiling Assistant](https://extensions.gnome.org/extension/3733/tiling-assistant/)
- [System Monitor](https://extensions.gnome.org/extension/6807/system-monitor/)
- [Weather Effect](https://extensions.gnome.org/extension/8848/weather-effect/)

## Optional Settings (Manual)

### Weekly TRIM (ext4 only)

Not needed on `btrfs` (modern kernels perform asynchronous TRIM automatically):

```bash
sudo systemctl enable --now fstrim.timer
```

### Snapper Snapshots (btrfs)

Requires the `@var_log` and `@pkg` subvolumes created during partitioning.

```bash
sudo pacman -S --needed snapper snap-pac

sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots

sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume create /mnt/btrfs-root/@snapshots
sudo umount /mnt/btrfs-root
sudo rmdir /mnt/btrfs-root

sudo mkdir /.snapshots
sudo mount -o noatime,compress=zstd:3,subvol=@snapshots /dev/nvme0n1p2 /.snapshots
sudo chmod 750 /.snapshots
sudo chown :wheel /.snapshots

echo "UUID=$(sudo blkid -s UUID -o value /dev/nvme0n1p2) /.snapshots btrfs noatime,compress=zstd:3,subvol=@snapshots 0 0" \
  | sudo tee -a /etc/fstab > /dev/null

sudo snapper -c root set-config \
  "TIMELINE_CREATE=yes" "TIMELINE_CLEANUP=yes" \
  "TIMELINE_LIMIT_HOURLY=5" "TIMELINE_LIMIT_DAILY=7" \
  "TIMELINE_LIMIT_WEEKLY=0" "TIMELINE_LIMIT_MONTHLY=0" "TIMELINE_LIMIT_YEARLY=0"

sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
```

> **After a snapshot rollback:** The kernel resides on the ESP (`/boot`) and is not included in Btrfs snapshots. If `/usr/lib/modules` in the rolled-back snapshot does not match the kernel on the ESP, boot from a matching kernel or Live ISO and reinstall the kernel package (`sudo pacman -S linux-zen`).

### Swapfile (for hibernation)

Not needed with 16+ GB RAM and `zram` unless you plan to use hibernation (which also requires the `resume` hook and `resume_offset`).

```bash
# For ext4
sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile

# For btrfs (create in a dedicated subvolume without snapshots)
sudo btrfs filesystem mkswapfile --size 8g /swapfile && sudo swapon /swapfile

# Add to fstab
echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab > /dev/null
```

Swap tuning (**without** zram only):

```bash
sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null << 'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
```

### Secure Boot (`sbctl`)

For `systemd-boot` with a signed kernel (Microsoft keys remain enrolled so Windows continues to boot).

1. Put your firmware into **Setup Mode** in UEFI settings (set Secure Boot mode to `Custom` and clear existing keys).

2. Install `sbctl`, generate keys, and enroll them alongside Microsoft's keys:

   ```bash
   sudo pacman -S --needed sbctl
   sbctl status
   sudo sbctl create-keys
   sudo sbctl enroll-keys -m
   ```

3. Sign the kernel and bootloader binaries (`-s` saves paths to the `sbctl` database so the pacman hook automatically re-signs them after updates):

   ```bash
   sudo sbctl sign -s /boot/vmlinuz-linux-zen
   sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
   sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
   sudo sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
   ```

4. Verify signatures:

   ```bash
   sudo sbctl verify 2>&1 | grep -E "vmlinuz|systemd-boot|BOOTX64"
   ```

## Quick System Checks

You can run `./arch-setup.sh check` or verify each component manually:

| Check | Command | Expected Output |
| --- | --- | --- |
| **NVIDIA params** | `sudo cat /proc/driver/nvidia/params` | Readable NVIDIA driver parameters |
| **NVIDIA DRM modeset** | `cat /sys/module/nvidia_drm/parameters/modeset` | `Y` |
| **NVIDIA suspend** | `sudo cat /proc/driver/nvidia/params \| grep UseKernelSuspendNotifiers` | `UseKernelSuspendNotifiers: 1` |
| **Active swap (zram)** | `swapon --show` | `/dev/zram0` active |
| **zswap disabled** | `cat /sys/module/zswap/parameters/enabled` | `N` |
| **Bootloader** | `bootctl status` | `systemd-boot` installed, Windows entry listed (if installed) |
| **Filesystem** | `findmnt -no OPTIONS /` | Includes `compress=zstd:3` and `subvol=/@` (for btrfs) |
| **Time sync** | `timedatectl` | `System clock synchronized: yes` |
| **KWallet (KDE)** | `qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.isOpen kdewallet` | `true` |
