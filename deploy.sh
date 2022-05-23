#!/bin/env bash
currentscript=$0
user=zeth
srcdir=/home/$user/.local/src
function finish {
echo "shredding ${currentscript}"; shred -u ${currentscript};
}

#whenver the script exits call the function "finish"
trap finish EXIT
function pacmantweaks {
echo "Enabling parallel downloads and candy for pacman"
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i '/ParallelDownloads/ a ILoveCandy' /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
tee /usr/share/libalpm/hooks/paccache.hook >/dev/null <<'EOF'
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
}
function procs {
nc=$(grep -c ^processor /proc/cpuinfo)
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -gt 8000000 ]]; then
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
fi
}
function vconsole {
echo "Writing settings to /etc/vconsole.conf in case I ever need to do things from TTY"
tee /etc/vconsole.conf >/dev/null <<'EOF'
KEYMAP=cz-qwertz
FONT=Lat2-Terminus16
EOF
echo "Setting X's locale to cz"
localectl set-x11-keymap cz
}
function microcodes {
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
}
function enableaur {
sudo -u "$user" mkdir -p "$srcdir/paru-bin"
sudo -u "$user" git clone --depth 1 "https://aur.archlinux.org/paru-bin.git" "$srcdir/paru" >/dev/null 2>&1 ||
{ cd "$srcdir/paru-bin" || return 1 ; sudo -u "$user" git pull --force origin master;}
cd "$srcdir/paru-bin"
sudo -u "$user" -D "$srcdir/paru-bin" makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}
