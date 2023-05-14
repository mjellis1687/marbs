#!/bin/sh
#
# Arch linux install script
# Original script by Luke Smith <luke@lukesmith.xyz>
# Modified by Matt Ellis
# License: GNU GPLv3
# The original script created a user and used dialog boxes, which have been
# removed

# Dependencies: sudo

### OPTIONS AND VARIABLES ###

usage() {
	printf "Required arguments:\\n  -u: Set user\\nOptional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n"
}
error() {
	printf "%s\n" "$1" >&2
	exit 1;
}

name=
while getopts ":a:r:b:p:h" o; do case "${o}" in
	r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit 1 ;;
	p) progsfile=${OPTARG} ;;
	a) aurhelper=${OPTARG} ;;
	u) name=${OPTARG} ;;
	h) usage && exit 0 ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && usage && exit 1 ;;
esac done

[ -z "$name" ] && error "Must provide a user"
repodir="/home/$name/.local/src"
mkdir -p "$repodir"
chown -R "$name":wheel "$(dirname "$repodir")"
[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/lukesmithxyz/voidrice.git"
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/mjellis1687/marbs/master/progs.csv"
[ -z "$aurhelper" ] && aurhelper="yay"

### FUNCTIONS ###

installpkg(){
	printf "Installing $1"
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

refreshkeys() { \
	pacman -Sy
	pacman --noconfirm -S archlinux-keyring
}

checkpkginstall() {
	printf "Checking if $1 is installed"
	(pacman -Qi "$1" > /dev/null 2>&1 || pacman -Qg "$1" > /dev/null 2>&1) && printf "$1 is installed" || (printf "$1 is not installed" && exit 1)
}

manualinstall() {
	# Installs $1 manually. Used only for AUR helper here.
	# Should be run after repodir is created and var is set.
	pacman -Qq "$1" && return 0
	printf "Installing $1 from AUR manually."
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{
			cd "$repodir/$1" || return 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$repodir/$1" || exit 1
	sudo -u "$name" -D "$repodir/$1" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

maininstall() {
	# Installs all needed programs from main repo.
	printf "Installing $1 ($n of $total). $1 $2"
	installpkg "$1"
}

gitmakeinstall() {
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	printf "Installing $progname ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		{
			cd "$dir" || return 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

aurinstall() {
	printf "Installing $1 ($n of $total) from the AUR. $1 $2"
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
	printf "Installing the Python package $1 ($n of $total). $1 $2"
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

installationloop() {
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
		curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
	total=$(wc -l </tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		echo "$comment" | grep -q "^\".*\"$" &&
			comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
		"A") aurinstall "$program" "$comment" ;;
		"G") gitmakeinstall "$program" "$comment" ;;
		"P") pipinstall "$program" "$comment" ;;
		*) maininstall "$program" "$comment" ;;
		esac
	done </tmp/progs.csv
}

putgitrepo() {
	# Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
	printf "Downloading and installing config files..."
	[ -z "$3" ] && branch="master" || branch="$repobranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 \
		--single-branch --no-tags -q --recursive -b "$branch" \
		--recurse-submodules "$1" "$dir"
	sudo -u "$name" cp -rfT "$dir" "$2"
}

vimplugininstall() {
	# TODO remove shortcuts error message
	# Installs vim plugins.
	printf "Installing neovim plugins..."
	mkdir -p "/home/$name/.config/nvim/autoload"
	curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" >  "/home/$name/.config/nvim/autoload/plug.vim"
	chown -R "$name:wheel" "/home/$name/.config/nvim"
	sudo -u "$name" nvim -c "PlugInstall|q|q"
}

finalize(){
	rm -f /tmp/progs.csv
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

name=`who am i | awk '{print $1}'`
printf "Running as user $name"

# Check if user is root on Arch distro. Install dialog.
! [ $(id -u) = 0 ] && error "Must run the script as root"

### The rest of the script requires no user input.

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl ca-certificates base-devel git ntp zsh; do
	checkpkginstall "$x" || (printf "Installing $x which is required to install and configure other programs." && installpkg "$x") || error "Failed to install $x"
done

printf "Synchronizing system time to ensure successful and secure installation of software..."
ntpd -q -g >/dev/null 2>&1

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
trap 'rm -f /etc/sudoers.d/marbs-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/marbs-temp

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall "$aurhelper" || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

# Install the dotfiles in the user's home directory, but remove .git dir and
# other unnecessary files.
if [ ! -f "/home/$name/.config/shell/profile" ]; then
	putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
	rm -rf "/home/$name/.git/" "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"
fi

# Install vim plugins if not alread present.
[ ! -f "/home/$name/.config/nvim/autoload/plug.vim" ] && vimplugininstall

# Most important command! Get rid of the beep!
rmmod pcspkr
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
sudo -u "$name" mkdir -p "/home/$name/.config/mpd/playlists/"

# Enable tap to click
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection' >/etc/X11/xorg.conf.d/40-libinput.conf

# Allow wheel users to sudo with password and allow several system commands
# (like `shutdown` to run without password).
echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-marbs-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount" >/etc/sudoers.d/01-marbs-cmds-without-password
# echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/pacman -S -u -y --config /etc/pacman.conf --,/usr/bin/pacman -S -y -u --config /etc/pacman.conf --" >/etc/sudoers.d/01-marbs-cmds-without-password
echo "Defaults editor=/usr/bin/nvim" >/etc/sudoers.d/02-marbs-visudo-editor
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf

# Last message! Install complete!
finalize
