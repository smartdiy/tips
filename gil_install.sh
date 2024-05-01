#! /usr/bin/env bash

script_rel_path="/home/tempuser"
script_full_path="$script_rel_path/"$(basename "$0")

# choose which part of the script should run based on cli argument
# no argument case
if [ -z "$1" ] ; then

    # assuming installed debian 12 system is mounted to /mnt
    mkdir "/mnt$script_rel_path"
    cp "$0" "/mnt$script_full_path"

    # mount essentials for chroot
    # https://wiki.debian.org/chroot
    mount --bind /dev /mnt/dev/
    mount --bind /dev/pts /mnt/dev/pts
    mount --bind /proc /mnt/proc
    mount --bind /sys  /mnt/sys
    mount --bind /run  /mnt/run

    # chroot and start the next part of this script from within the chroot
    # couldn't get this part to work right
    #chroot /mnt /bin/bash -i "$script_full_path 1"
    
    echo "After chroot, enter command: cd $script_rel_path; bash $script_full_path 1"
    chroot /mnt
fi

if [ "$1" == 1 ] ; then

    echo "Installing build packages"
    apt install -y gnulib libdevmapper-dev libfreetype-dev gettext autogen git bison help2man texinfo efibootmgr libisoburn1 libisoburn-dev mtools pkg-config m4 libtool automake autoconf flex fuse3 libfuse3-dev gawk

    # mawk gives make error, so using gawk
    mv /usr/bin/mawk /usr/bin/mawk_bu
    ln -s /usr/bin/gawk /usr/bin/mawk

    # git clone needed repos
    git clone https://git.savannah.gnu.org/git/grub.git
    cd grub
    git clone https://git.savannah.nongnu.org/git/grub-extras.git
    git clone https://aur.archlinux.org/grub-improved-luks2-git.git
    git clone https://git.savannah.gnu.org/git/gnulib.git

    cp "$0" "./"$(basename "$0")

    /bin/bash -i $(basename "$0") 2
fi

if [ "$1" == 2 ] ; then

    echo "Compiling grub"

    # This part is copied from grub-improved-luks2-git/PKGBUILD
    # It patches grub and compiles and installes it

    patch -Np1 -i ./grub-improved-luks2-git/add-GRUB_COLOR_variables.patch

    # Patch grub-mkconfig to detect Arch Linux initramfs images.
    patch -Np1 -i ./grub-improved-luks2-git/detect-archlinux-initramfs.patch

    # argon2
    patch -Np1 -i ./grub-improved-luks2-git/argon_1.patch
    patch -Np1 -i ./grub-improved-luks2-git/argon_2.patch
    patch -Np1 -i ./grub-improved-luks2-git/argon_3.patch
    patch -Np1 -i ./grub-improved-luks2-git/argon_4.patch
    patch -Np1 -i ./grub-improved-luks2-git/argon_5.patch

    # make grub-install work with luks2
    patch -Np1 -i ./grub-improved-luks2-git/grub-install_luks2.patch

    # Fix DejaVuSans.ttf location so that grub-mkfont can create *.pf2 files for starfield theme.
    sed 's|/usr/share/fonts/dejavu|/usr/share/fonts/dejavu /usr/share/fonts/TTF|g' -i "configure.ac"

    # Modify grub-mkconfig behaviour to silence warnings FS#36275
    sed 's| ro | rw |g' -i "util/grub.d/10_linux.in"

    # Modify grub-mkconfig behaviour so automatically generated entries read 'Arch Linux' FS#33393
    sed 's|GNU/Linux|Linux|' -i "util/grub.d/10_linux.in"

    # Pull in latest language files
    #[ ! -z "$GRUB_ENABLE_NLS" ] && ./linguas.sh

    # Remove lua module from grub-extras as it is incompatible with changes to grub_file_open
    # http://git.savannah.gnu.org/cgit/grub.git/commit/?id=ca0a4f689a02c2c5a5e385f874aaaa38e151564e
    rm -rf ./grub-extras/lua

    export GRUB_CONTRIB=./grub-extras
    export GNULIB_SRCDIR=./gnulib
    CFLAGS=${CFLAGS/-fno-plt}

    ./bootstrap
    mkdir ./build_x86_64-efi
    cd ./build_x86_64-efi
    ../configure --with-platform=efi --target=x86_64 --prefix="/usr" --sbindir="/usr/bin" --sysconfdir="/etc" --enable-boot-time --enable-cache-stats --enable-device-mapper --enable-grub-mkfont --enable-grub-mount --enable-mm-debug --disable-silent-rules --disable-werror  CPPFLAGS="$CPPFLAGS -O2"
    make

    cd ..
    # now we should be in /home/tempuser/grub (on the mounted filesystem)
    /bin/bash -i $(basename "$0") 3
fi

if [ "$1" == 3 ] ; then

    echo "Installing grub"
#    exit

    cd ./build_x86_64-efi
    make DESTDIR=/ bashcompletiondir=/usr/share/bash-completion/completions install
    install -D -m0644 ../grub-improved-luks2-git/grub.default /etc/default/grub

fi

