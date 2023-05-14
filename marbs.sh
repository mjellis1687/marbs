#!/bin/sh
# Matt's Auto Rice Boostrapping Script (marbs)
# original script by Luke Smith <luke@lukesmith.xyz>
# modified by Matt Ellis
# License: GNU GPLv3
# The original script created a user and used dialog boxes, which have been
# removed

# Dependencies: sudo

### OPTIONS AND VARIABLES ###

while getopts ":a:r:b:p:h" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit 1 ;;
	r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit 1 ;;
	p) progsfile=${OPTARG} ;;
	a) aurhelper=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit 1 ;;
esac done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/mjellis1687/dotFiles.git"
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/mjellis1687/marbs/master/progs.csv"
[ -z "$aurhelper" ] && aurhelper="yay"

### FUNCTIONS ###

installpkg(){
	echo "Installing $1"
	pacman --noconfirm --needed -S "$1"
}

error() { printf "%s\n" "$1" >&2; exit 1; }

refreshkeys() { \
	pacman -Sy
	pacman --noconfirm -S archlinux-keyring
}

restoreperms() {
	sed -i "/#marbs/d" /etc/sudoers
}

newperms() { # Set special sudoers settings for install (or after).
	restoreperms
	echo "$* #marbs" >> /etc/sudoers
}

checkpkginstall() {
	echo "Checking if $1 is installed"
	(pacman -Qi "$1" > /dev/null 2>&1 || pacman -Qg "$1" > /dev/null 2>&1) && echo "$1 is installed" || (echo "$1 is not installed" && exit 1)
}

manualinstall() { # Installs $1 manually if not installed. Used only for AUR helper here.
	[ -f "/usr/bin/$1" ] || (
		echo "Installing $1, an AUR helper..."
		# TODO: fix see updates
		repodir=/tmp
		sudo -u "$name" mkdir -p "$repodir/$1"
		sudo -u "$name" git clone --depth 1 "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
			{ cd "$repodir/$1" || return 1 ; sudo -u "$name" git pull --force origin ;}
		cd "$repodir/$1"
		sudo -u "$name" -D "$repodir/$1" makepkg --noconfirm -si || return 1
	)
}

maininstall() { # Installs all needed programs from main repo.
	echo "Installing $1 ($n of $total). $1 $2"
	installpkg "$1"
}

gitmakeinstall() {
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	echo "Installing $progname ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2"
	# This should check if the main branch is master or main
	git clone --depth 1 "$1" "$dir" || { cd "$dir" || return 1 ; git pull --force origin master;}
	cd "$dir" || exit 1
	make
	make install
	cd /tmp || return 1
}

aurinstall() {
	echo "Installing $1 ($n of $total) from the AUR. $1 $2"
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1"
}

pipinstall() {
	echo "Installing the Python package $1 ($n of $total). $1 $2"
	[ -x "$(command -v "pip")" ] || installpkg python-pip
	yes | pip install "$1"
}

installationloop() {
	# TODO: delete empty lines in progs.csv
	cat "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	# TODO: Check if program is already installed
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") checkpkginstall "$program" || aurinstall "$program" "$comment" ;;
			"G") checkpkginstall "$program" || gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			*) checkpkginstall "$program" || maininstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv
}

# putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
# 	dialog --infobox "Downloading and installing config files..." 4 60
# 	[ -z "$3" ] && branch="master" || branch="$repobranch"
# 	dir=$(mktemp -d)
# 	[ ! -d "$2" ] && mkdir -p "$2"
# 	chown "$name":wheel "$dir" "$2"
# 	git clone --recursive -b "$branch" --depth 1 --recurse-submodules "$1" "$dir" >/dev/null 2>&1
# 	cp -rfT "$dir" "$2"
# 	}

finalize(){
	rm -f /tmp/progs.csv
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

name=`who am i | awk '{print $1}'`
echo "Running as user $name"

# Check if user is root on Arch distro. Install dialog.
! [ $(id -u) = 0 ] && error "Must run the script as root"

### The rest of the script requires no user input.

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl base-devel git ntp; do
	checkpkginstall "$x" || (echo "Installing $x which is required to install and configure other programs." && installpkg "$x") || error "Failed to install $x"
done

echo "Synchronizing system time to ensure successful and secure installation of software..."
ntpdate 0.us.pool.ntp.org

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and $aurhelper colorful and adds eye candy on the progress bar
grep -q "^Color" /etc/pacman.conf || sed -i "s/^#Color$/Color/" /etc/pacman.conf
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
# Make pacman download packages in parallel
# TODO:
grep -q "^ParallelDownloads" /etc/pacman.conf || sed -i "s/^#ParallelDownloads.*/ParallelDownloads = 5/" /etc/pacman.conf

# Use all cores for compilation.
# sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall "$aurhelper" || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

restoreperms
finalize

# dialog --title "marbs Installation" --infobox "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes." 5 70
# yes | sudo -u "$name" $aurhelper -S libxft-bgra-git >/dev/null 2>&1

# Install the dotfiles in the user's home directory
#TODO: fix here
# putgitrepo "$dotfilesrepo" "/home/$name"
# rm -f "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"
# Create default urls file if none exists.
# [ ! -f "/home/$name/.config/newsboat/urls" ] && echo "http://lukesmith.xyz/rss.xml
# https://notrelated.libsyn.com/rss
# https://www.youtube.com/feeds/videos.xml?channel_id=UC2eYFnH61tmytImy1mTYvhA \"~Luke Smith (YouTube)\"
# https://www.archlinux.org/feeds/news/" > "/home/$name/.config/newsboat/urls"
# make git ignore deleted LICENSE & README.md files
# git update-index --assume-unchanged "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Most important command! Get rid of the beep!
# systembeepoff

# Make zsh the default shell for the user.
# chsh -s /bin/zsh "$name" >/dev/null 2>&1
# sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# dbus UUID must be generated for Artix runit.
# dbus-uuidgen > /var/lib/dbus/machine-id

# Use system notifications for Brave on Artix
# echo "export \$(dbus-launch)" > /etc/profile.d/dbus.sh

# Tap to click
# [ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
#         Identifier "libinput touchpad catchall"
#         MatchIsTouchpad "on"
#         MatchDevicePath "/dev/input/event*"
#         Driver "libinput"
# 	# Enable left mouse button by tapping
# 	Option "Tapping" "on"
# EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

# Fix fluidsynth/pulseaudio issue.
# grep -q "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" /etc/conf.d/fluidsynth ||
# 	echo "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" >> /etc/conf.d/fluidsynth

# Start/restart PulseAudio.
# pkill -15 -x 'pulseaudio'; sudo -u "$name" pulseaudio --start

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
# "%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/paru,/usr/bin/pacman -Syyuw --noconfirm"
