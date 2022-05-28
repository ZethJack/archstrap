#!/bin/env bash
currentscript=$0
while getopts ":a:r:b:p:h" o; do case "${o}" in
    h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit 1 ;;
    r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit 1 ;;
    b) repobranch=${OPTARG} ;;
    p) progsfile=${OPTARG} ;;
    a) aurhelper=${OPTARG} ;;
    *) printf "Invalid option: -%s\\n" "$OPTARG" && exit 1 ;;
esac done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/ZethJack/dotfiles.git"
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/ZethJack/archstrap/master/progs.csv"
[ -z "$aurhelper" ] && aurhelper="paru-bin"
[ -z "$repobranch" ] && repobranch="master"
finish() {
    echo "shredding ${currentscript}"; shred -u ${currentscript};
}

#whenver the script exits call the function "finish"
trap finish EXIT
installpkg(){ pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 ;}
manualinstall() { \
    dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
    sudo -u "$name" mkdir -p "$repodir/$1"
    sudo -u "$name" git clone --depth 1 "https://aur.archlinux.org/$1.git" "$repodir/$1" >/dev/null 2>&1 ||
        { cd "$repodir/$1" || return 1 ; sudo -u "$name" git pull --force origin master;}
    cd "$repodir/$1"
    sudo -u "$name" -D "$repodir/$1" makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}
maininstall() { \
    dialog --title "LARBS Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
    installpkg "$1"
    }
gitmakeinstall() {
    progname="$(basename "$1" .git)"
    dir="$repodir/$progname"
    dialog --title "LARBS Installation" --infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
    sudo -u "$name" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin master;}
    cd "$dir" || exit 1
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /tmp || return 1 ;}
aurinstall() { \
    dialog --title "LARBS Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
    echo "$aurinstalled" | grep -q "^$1$" && return 1
    sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
    }
pipinstall() { \
    dialog --title "LARBS Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
    [ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
    yes | pip install "$1"
    }
installationloop() { \
    ([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
    total=$(wc -l < /tmp/progs.csv)
    aurinstalled=$(pacman -Qqm)
    while IFS=, read -r tag program comment; do
        n=$((n+1))
        echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
        case "$tag" in
            "A") aurinstall "$program" "$comment" ;;
            "G") gitmakeinstall "$program" "$comment" ;;
            "P") pipinstall "$program" "$comment" ;;
            *) maininstall "$program" "$comment" ;;
        esac
    done < /tmp/progs.csv ;}
error() { printf "%s\n" "$1" >&2; exit 1; }
welcomemsg() { \
    dialog --title "Welcome!" --msgbox "Welcome to Zeth's Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured Linux desktop, which I use as my main machine.\\n\\n-Luke" 10 60

    dialog --colors --title "Important Note!" --yes-label "All ready!" --no-label "Return..." --yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}
pacmantweaks() { \
    dialog --infobox "Enabling parallel downloads and candy for pacman" 5 70
    grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
    sed -i "/^#ParallelDownloads/s/=.*/= 5/;s/^#Color$/Color/" /etc/pacman.conf
    dialog --infobox "Adding paccache hook" 5 70
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
makeflags() {\
    dialog --infobox "Detecting number of cores and adjusting makeflags" 5 70
    nc=$(grep -c ^processor /proc/cpuinfo)
    TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
    if [[  $TOTAL_MEM -gt 8000000 ]]; then
        sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
        sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
    fi
}
vcons() {\
    dialog --infobox "Writing settings to /etc/vconsole.conf in case I ever need to do things from TTY" 5 70
    tee /etc/vconsole.conf >/dev/null <<'EOF'
    KEYMAP=cz-qwertz
    FONT=Lat2-Terminus16
EOF
    localectl set-x11-keymap cz
}
microcode() {\
    dialog --infobox "Installing microcodes for CPU" 5 70
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
getuserandpass() { \
    # Prompts user for new username an password.
    name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
    while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
        name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
    pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    while ! [ "$pass1" = "$pass2" ]; do
        unset pass2
        pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
        pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    done ;}

usercheck() { \
    ! { id -u "$name" >/dev/null 2>&1; } ||
    dialog --colors --title "WARNING!" --yes-label "CONTINUE" --no-label "No wait..." --yesno "The user \`$name\` already exists on this system. LARBS can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nLARBS will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that LARBS will change $name's password to the one you just gave." 14 70
    }

preinstallmsg() { \
    dialog --title "Let's get this party started!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit 1; }
    }

adduserandpass() { \
    # Adds user `$name` with password $pass1.
    dialog --infobox "Adding user \"$name\"..." 4 50
    useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
    export repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
    echo "$name:$pass1" | chpasswd
    unset pass1 pass2 ;}

refreshkeys() { \
    case "$(readlink -f /sbin/init)" in
        *systemd* )
            dialog --infobox "Refreshing Arch Keyring..." 4 40
            pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
            ;;
        *)
            dialog --infobox "Enabling Arch Repositories..." 4 40
            pacman --noconfirm --needed -S artix-keyring artix-archlinux-support >/dev/null 2>&1
            for repo in extra community; do
                grep -q "^\[$repo\]" /etc/pacman.conf ||
                    echo "[$repo]
Include = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
            done
            pacman -Sy >/dev/null 2>&1
            pacman-key --populate archlinux >/dev/null 2>&1
            ;;
    esac ;}
newperms() { \
    sed -i "/#LARBS/d" /etc/sudoers
    echo "$* #LARBS" >> /etc/sudoers ;}
putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
    dialog --infobox "Downloading and installing config files..." 4 60
    [ -z "$3" ] && branch="master" || branch="$repobranch"
    dir=$(mktemp -d)
    [ ! -d "$2" ] && mkdir -p "$2"
    chown "$name":wheel "$dir" "$2"
    sudo -u "$name" git clone --bare --recursive -b "$branch" --depth 1 --recurse-submodules "$1" "$dir" >/dev/null 2>&1
    sudo -u "$name" cp -rfT "$dir" "$2"
}
systembeepoff() { dialog --infobox "Getting rid of PCM speaker error beep sound..." 10 50
    rmmod pcspkr
    echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}
finalize(){ \
    dialog --infobox "Preparing welcome message..." 4 50
    dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n.t Luke" 12 80
    }
# Check if user is root on Arch distro. Install dialog.
pacman --noconfirm --needed -Sy dialog || error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Welcome user and pick dotfiles.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl ca-certificates base-devel git ntp zsh ; do
	dialog --title "ZBS Installation" --infobox "Installing \`$x\` which is required to install and configure other programs." 5 70
	installpkg "$x"
done

dialog --title "ZBS Installation" --infobox "Synchronizing system time to ensure successful and secure installation of software..." 4 70
ntpdate 0.us.pool.ntp.org >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
pacmantweaks || error "Error, pacman tweaks could not be completed."

makeflags || error "Error, could not adjust cores and makeflags."

manualinstall paru-bin || error "Failed to install AUR helper."

installationloop

dialog --title "LARBS Installation" --infobox "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes." 5 70
yes | sudo -u "$name" $aurhelper -S libxft-bgra-git >/dev/null 2>&1

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name/.cfg" "$repobranch"
rm -f "/home/$name/.cfg/README.md" "/home/$name/.cfg/LICENSE" "/home/$name/.cfg/FUNDING.yml"
# Create default urls file if none exists.
[ ! -f "/home/$name/.config/newsboat/urls" ] && echo "http://lukesmith.xyz/rss.xml
https://videos.lukesmith.xyz/feeds/videos.xml?videoChannelId=2
https://lindypress.net/rss.xml
https://notrelated.xyz/rss.xml
https://www.youtube.com/feeds/videos.xml?channel_id=UC2eYFnH61tmytImy1mTYvhA \"~Luke Smith (YouTube)\"
https://www.archlinux.org/feeds/news/" > "/home/$name/.config/newsboat/urls"
# make git ignore deleted LICENSE & README.md files
git update-index --assume-unchanged "/home/$name/.cfg/README.md" "/home/$name/.cfg/LICENSE" "/home/$name/.cfg/FUNDING.yml"

# Most important command! Get rid of the beep!
systembeepoff

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# dbus UUID must be generated for Artix runit.
dbus-uuidgen > /var/lib/dbus/machine-id

# Use system notifications for Brave on Artix
echo "export \$(dbus-launch)" > /etc/profile.d/dbus.sh

# Tap to click
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

# Fix fluidsynth/pulseaudio issue.
grep -q "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" /etc/conf.d/fluidsynth ||
	echo "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" >> /etc/conf.d/fluidsynth

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL #LARBS
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/paru,/usr/bin/pacman -Syyuw --noconfirm"

# Last message! Install complete!
finalize
clear
