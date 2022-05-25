#!/bin/env bash
echo -ne "
################################################
Enabling parallel downloads and candy for pacman
################################################
"
sudo sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sudo sed -i '/ParallelDownloads/ a ILoveCandy' /etc/pacman.conf
echo -ne "
#########################################################
Enablng paccache hook to automatically clean pacman cache
#########################################################
"
sudo tee /usr/share/libalpm/hooks/paccache.hook >/dev/null <<'EOF'
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Cleaning pacman cache with paccache …
When = PostTransaction
Exec = /usr/bin/paccache -r
EOF
pacman -Sy --noconfirm --needed
echo -ne "
#################################################
Detecting number of cores and adjusting makeflags
#################################################
"
nc=$(grep -c ^processor /proc/cpuinfo)
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -gt 8000000 ]]; then
    sudo sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
    sudo sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
fi
echo -ne "
################################################################################
Writing settings to /etc/vconsole.conf in case I ever need to do things from TTY
################################################################################
"
sudo tee /etc/vconsole.conf >/dev/null <<'EOF'
KEYMAP=cz-qwertz
FONT=Lat2-Terminus16
EOF
echo -ne"
########################
Setting X's locale to cz
########################
"
localectl set-x11-keymap cz
echo -ne "
#############################
Installing microcodes for CPU
#############################
"
proc_type=$(lscpu)
if grep -E "GenuineIntel" <<< ${proc_type}; then
    echo "Installing Intel microcode"
    pacman -S --noconfirm --needed intel-ucode
    proc_ucode=intel-ucode.img
elif grep -E "AuthenticAMD" <<< ${proc_type}; then
    echo "Installing AMD microcode"
    pacman -S --noconfirm --needed amd-ucode
    proc_ucode=amd-ucode.img
fi
echo -ne "
#################################
Installing Paru-bin an AUR helper
#################################
"
mkdir -p "$srcdir/paru-bin"
git clone --depth 1 "https://aur.archlinux.org/paru-bin.git" "$srcdir/paru" >/dev/null 2>&1 ||
{ cd "$srcdir/paru-bin" || return 1 ; git pull --force origin master;}
cd "$srcdir/paru-bin" || return 1
sudo -D "$srcdir/paru-bin" makepkg --noconfirm -si >/dev/null 2>&1 || return 1
