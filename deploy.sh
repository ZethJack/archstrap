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
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i '/ParallelDownloads/ a ILoveCandy' /etc/pacman.conf
    dialog --infobox "Enabling paccache hook to automatically clean pacman cache" 5 70
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
        sudo sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
        sudo sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
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

