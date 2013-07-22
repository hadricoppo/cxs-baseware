#!/tools/bin/bash

function setup_dirs {

LFS=$(pwd)/cxs-baseware
mkdir -v $LFS/{dev,proc,sys}
mknod -m 600 $LFS/dev/console c 5 1
mknod -m 666 $LFS/dev/null c 1 3
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts $LFS/dev/pts
mount -vt tmpfs shm $LFS/dev/shm
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys

}

function setup_env {

set +h
umask 022
HOME_DIR=$(pwd)
LFS=${HOME_DIR}/cxs-baseware/
PACKAGES_DIR=/packages/
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
export LFS LC_ALL LFS_TGT PATH PACKAGES_DIR
chroot "$LFS" /tools/bin/env -i HOME=/root TERM="$TERM" PS1='\u:\w\$ ' PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin CXS_BUILDD=1 /build_system.sh

}

function prepare {

set +h


}

function create_dirs {

mkdir -pv /{bin,boot,etc/{opt,sysconfig},home,lib,mnt,opt,run}
mkdir -pv /{media/{floppy,cdrom},sbin,srv,var}
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp
mkdir -pv /usr/{,local/}{bin,include,lib,sbin,src}
mkdir -pv /usr/{,local/}share/{doc,info,locale,man}
mkdir -v  /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
for dir in /usr /usr/local; do
  ln -sv share/{man,doc,info} $dir
done
case $(uname -m) in
 x86_64) ln -sv lib /lib64 && ln -sv lib /usr/lib64 ;;
esac
mkdir -v /var/{log,mail,spool}
ln -sv /run /var/run
ln -sv /run/lock /var/lock
mkdir -pv /var/{opt,cache,lib/{misc,locate},local}


ln -sv /tools/bin/{bash,cat,echo,pwd,stty} /bin
ln -sv /tools/bin/perl /usr/bin
ln -sv /tools/lib/libgcc_s.so{,.1} /usr/lib
ln -sv /tools/lib/libstdc++.so{,.6} /usr/lib
sed 's/tools/usr/' /tools/lib/libstdc++.la > /usr/lib/libstdc++.la
ln -sv bash /bin/sh


touch /etc/mtab


cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF


cat > /etc/group << "EOF"
root:x:0:
bin:x:1:
sys:x:2:
kmem:x:3:
tty:x:4:
tape:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
mail:x:34:
nogroup:x:99:
EOF

touch /var/run/utmp /var/log/{btmp,lastlog,wtmp}
chgrp -v utmp /var/run/utmp /var/log/lastlog
chmod -v 664 /var/run/utmp /var/log/lastlog
chmod -v 600 /var/log/btmp

}

function build_linux_headers {

cd ${PACKAGES_DIR}
tar xvf linux-3.2.6.tar.xz
cd linux-3.2.6
make mrproper
make headers_check
make INSTALL_HDR_PATH=dest headers_install
find dest/include \( -name .install -o -name ..install.cmd \) -delete
cp -rv dest/include/* /usr/include
cd ${PACKAGES_DIR}
rm -rf linux-3.2.6

}

function build_glibc {

cd ${PACKAGES_DIR}
tar xvf glibc-2.14.1.tar.bz2
cd glibc-2.14.1

DL=$(readelf -l /bin/sh | sed -n 's@.*interpret.*/tools\(.*\)]$@\1@p')
sed -i "s|libs -o|libs -L/usr/lib -Wl,-dynamic-linker=$DL -o|" \
        scripts/test-installation.pl
unset DL

sed -i -e 's/"db1"/& \&\& $name ne "nss_test1"/' scripts/test-installation.pl

sed -i 's|@BASH@|/bin/bash|' elf/ldd.bash.in

patch -Np1 -i ../glibc-2.14.1-fixes-1.patch
patch -Np1 -i ../glibc-2.14.1-sort-1.patch

patch -Np1 -i ../glibc-2.14.1-gcc_fix-1.patch

sed -i '195,213 s/PRIVATE_FUTEX/FUTEX_CLOCK_REALTIME/' nptl/sysdeps/unix/sysv/linux/x86_64/pthread_rwlock_timed{rd,wr}lock.S

mkdir -v ../glibc-build
cd ../glibc-build

case `uname -m` in
  i?86) echo "CFLAGS += -march=i486 -mtune=native -O3 -pipe" > configparms ;;
esac

../glibc-2.14.1/configure --prefix=/usr --disable-profile --enable-add-ons --enable-kernel=2.6.25 --libexecdir=/usr/lib/glibc

make

touch /etc/ld.so.conf
make install

cp -v ../glibc-2.14.1/sunrpc/rpc/*.h /usr/include/rpc
cp -v ../glibc-2.14.1/sunrpc/rpcsvc/*.h /usr/include/rpcsvc
cp -v ../glibc-2.14.1/nis/rpcsvc/*.h /usr/include/rpcsvc

mkdir -pv /usr/lib/locale

}

function configure_glibc {

cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF

cp -v --remove-destination /usr/share/zoneinfo/Universal /etc/localtime

cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF

cat >> /etc/ld.so.conf << "EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF
mkdir /etc/ld.so.conf.d



}

function adjust_toolchain {

mv -v /tools/bin/{ld,ld-old}
mv -v /tools/$(gcc -dumpmachine)/bin/{ld,ld-old}
mv -v /tools/bin/{ld-new,ld}
ln -sv /tools/bin/ld /tools/$(gcc -dumpmachine)/bin/ld

gcc -dumpspecs | sed -e 's@/tools@@g' -e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' -e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' > `dirname $(gcc --print-libgcc-file-name)`/specs

}

function build_zlib {

cd ${PACKAGES_DIR}
tar xvf zlib-1.2.7.tar.bz2
cd zlib-1.2.7

./configure --prefix=/usr
make
make install

cd ${PACKAGES_DIR}
rm -rf zlib-1.2.7

}

function build_sed {

cd ${PACKAGES_DIR}
tar xvf sed-4.2.1.tar.bz2
cd sed-4.2.1

./configure --prefix=/usr --bindir=/bin --htmldir=/usr/share/doc/sed-4.2.1

make
make install

cd ${PACKAGES_DIR}
rm -rf sed-4.2.1

}

function build_ncurses {

cd ${PACKAGES_DIR}
tar xvf ncurses-5.9.tar.gz
cd ncurses-5.9

./configure --prefix=/usr --with-shared --without-debug --enable-widec

make
make install

mv -v /usr/lib/libncursesw.so.5* /lib

ln -sfv ../../lib/libncursesw.so.5 /usr/lib/libncursesw.so

for lib in ncurses form panel menu ; do \
    rm -vf /usr/lib/lib${lib}.so ; \
    echo "INPUT(-l${lib}w)" >/usr/lib/lib${lib}.so ; \
    ln -sfv lib${lib}w.a /usr/lib/lib${lib}.a ; \
done
ln -sfv libncurses++w.a /usr/lib/libncurses++.a

rm -vf /usr/lib/libcursesw.so
echo "INPUT(-lncursesw)" >/usr/lib/libcursesw.so
ln -sfv libncurses.so /usr/lib/libcurses.so
ln -sfv libncursesw.a /usr/lib/libcursesw.a
ln -sfv libncurses.a /usr/lib/libcurses.a

cd ${PACKAGES_DIR}
rm -rf ncurses-5.9


}

function build_util_linux {

cd ${PACKAGES_DIR}
tar xvf util-linux-2.20.1.tar.bz2
cd util-linux-2.20.1

sed -e 's@etc/adjtime@var/lib/hwclock/adjtime@g' -i $(grep -rl '/etc/adjtime' .)
mkdir -pv /var/lib/hwclock

./configure --enable-arch --enable-partx --enable-write

make
make install

cd ${PACKAGES_DIR}
rm -rf util-linux-2.20.1

}

function build_psmisc {

cd ${PACKAGES_DIR}
tar xvf psmisc-22.15.tar.gz
cd psmisc-22.15
./configure --prefix=/usr
make
make install
mv -v /usr/bin/fuser /bin
mv -v /usr/bin/killall /bin
cd ${PACKAGES_DIR}
rm -rf psmisc-22.15

}

function build_e2fsprogs {

cd ${PACKAGES_DIR}
tar xvf e2fsprogs-1.42.tar.gz
cd e2fsprogs-1.42

mkdir -v build
cd build

PKG_CONFIG=/tools/bin/true LDFLAGS="-lblkid -luuid" ../configure --prefix=/usr --with-root-prefix="" --enable-elf-shlibs --disable-libblkid --disable-libuuid --disable-uuidd --disable-fsck

make
make install
make install-libs

chmod -v u+w /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a

cd ${PACKAGES_DIR}
rm -rf e2fsprogs-1.42

}

function build_coreutils {

cd ${PACKAGES_DIR}
tar xvf coreutils-8.15.tar.xz
cd coreutils-8.15

case `uname -m` in
 i?86 | x86_64) patch -Np1 -i ../coreutils-8.15-uname-1.patch ;;
esac

patch -Np1 -i ../coreutils-8.15-i18n-1.patch

./configure --prefix=/usr --libexecdir=/usr/lib --enable-no-install-program=kill,uptime

make
make install

mv -v /usr/bin/{cat,chgrp,chmod,chown,cp,date,dd,df,echo} /bin
mv -v /usr/bin/{false,ln,ls,mkdir,mknod,mv,pwd,rm} /bin
mv -v /usr/bin/{rmdir,stty,sync,true,uname} /bin
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/bin/{head,sleep,nice} /bin

cd ${PACKAGES_DIR}
rm -rf coreutils-8.15

}

function build_iana_etc {

cd ${PACKAGES_DIR}
tar xvf iana-etc-2.30.tar.bz2
cd iana-etc-2.30

make
make install

cd ${PACKAGES_DIR}
rm -rf iana-etc-2.30

}

function build_bison {

cd ${PACKAGES_DIR}
tar xvf bison-2.5.tar.bz2
cd bison-2.5

./configure --prefix=/usr

echo '#define YYENABLE_NLS 1' >> lib/config.h

make
make install

cd ${PACKAGES_DIR}
rm -rf bison-2.5

}

function build_grep {

cd ${PACKAGES_DIR}
tar xvf grep-2.10.tar.xz
cd grep-2.10

./configure --prefix=/usr --bindir=/bin

make
make install

cd ${PACKAGES_DIR}
rm -rf grep-2.10

}

function build_procps {

cd ${PACKAGES_DIR}
tar xvf procps-3.2.8.tar.gz
cd procps-3.2.8

patch -Np1 -i ../procps-3.2.8-fix_HZ_errors-1.patch
patch -Np1 -i ../procps-3.2.8-watch_unicode-1.patch
sed -i -e 's@\*/module.mk@proc/module.mk ps/module.mk@' Makefile
make
make install

cd ${PACKAGES_DIR}
rm -rf procps-3.2.8

}

function build_readline {

cd ${PACKAGES_DIR}
tar xvf readline-6.2.tar.gz
cd readline-6.2

sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install

patch -Np1 -i ../readline-6.2-fixes-1.patch

./configure --prefix=/usr --libdir=/lib

make SHLIB_LIBS=-lncurses
make install

mv -v /lib/lib{readline,history}.a /usr/lib

rm -v /lib/lib{readline,history}.so
ln -sfv ../../lib/libreadline.so.6 /usr/lib/libreadline.so
ln -sfv ../../lib/libhistory.so.6 /usr/lib/libhistory.so

mkdir   -v       /usr/share/doc/readline-6.2
install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-6.2

cd ${PACKAGES_DIR}
rm -rf readline-6.2

}

function build_bash {

cd ${PACKAGES_DIR}
tar xvf bash-4.2.tar.gz
cd bash-4.2

patch -Np1 -i ../bash-4.2-fixes-4.patch
./configure --prefix=/usr --bindir=/bin --htmldir=/usr/share/doc/bash-4.2 --without-bash-malloc --with-installed-readline

make
make install

cd ${PACKAGES_DIR}
rm -rf bash-4.2

}

function build_libtool {

cd ${PACKAGES_DIR}
tar xvf libtool-2.4.2.tar.gz
cd libtool-2.4.2

./configure --prefix=/usr

make
make install

cd ${PACKAGES_DIR}
rm -rf libtool-2.4.2

}

function build_inetutils {

cd ${PACKAGES_DIR}
tar xvf inetutils-1.9.1.tar.gz
cd inetutils-1.9.1

./configure --prefix=/usr --libexecdir=/usr/sbin --localstatedir=/var --disable-ifconfig --disable-logger --disable-syslogd --disable-whois --disable-servers

make
make install

mv -v /usr/bin/{hostname,ping,ping6} /bin
mv -v /usr/bin/traceroute /sbin

cd ${PACKAGES_DIR}
rm -rf inetutils-1.9.1

}

function build_findutils {

cd ${PACKAGES_DIR}
tar xvf findutils-4.4.2.tar.gz
cd findutils-4.4.2

./configure --prefix=/usr --libexecdir=/usr/lib/findutils --localstatedir=/var/lib/locate

make
make install

mv -v /usr/bin/find /bin
sed -i 's/find:=${BINDIR}/find:=\/bin/' /usr/bin/updatedb

cd ${PACKAGES_DIR}
rm -rf findutils-4.4.2

}

function build_flex {

cd ${PACKAGES_DIR}
tar xvf flex-2.5.35.tar.bz2
cd flex-2.5.35

patch -Np1 -i ../flex-2.5.35-gcc44-1.patch

./configure --prefix=/usr

make
make install

ln -sv libfl.a /usr/lib/libl.a

cat > /usr/bin/lex << "EOF"
#!/bin/sh
# Begin /usr/bin/lex

exec /usr/bin/flex -l "$@"

# End /usr/bin/lex
EOF
chmod -v 755 /usr/bin/lex

cd ${PACKAGES_DIR}
rm -rf flex-2.5.35

}

function build_xz {

cd ${PACKAGES_DIR}
tar xvf xz-5.0.3.tar.bz2
cd xz-5.0.3

./configure --prefix=/usr --libdir=/lib --docdir=/usr/share/doc/xz-5.0.3

make
make pkgconfigdir=/usr/lib/pkgconfig install

cd ${PACKAGES_DIR}
rm -rf xz-5.0.3

}

function build_grub {

cd ${PACKAGES_DIR}
tar xvf grub-1.99.tar.gz
cd grub-1.99

./configure --prefix=/usr --sysconfdir=/etc --disable-grub-emu-usb --disable-efiemu --disable-werror

make
make install

cd ${PACKAGES_DIR}
rm -rf grub-1.99

}

function build_iproute2 {

cd ${PACKAGES_DIR}
tar xvf iproute2-3.2.0.tar.xz
cd iproute2-3.2.0

sed -i '/^TARGETS/s@arpd@@g' misc/Makefile
sed -i /ARPD/d Makefile
rm man/man8/arpd.8

sed -i -e '/netlink\//d' ip/ipl2tp.c

make DESTDIR=

make DESTDIR= MANDIR=/usr/share/man DOCDIR=/usr/share/doc/iproute2-3.2.0 install

cd ${PACKAGES_DIR}
rm -rf iproute2-3.2.0

}

function build_kbd {

cd ${PACKAGES_DIR}
tar xvf kbd-1.15.2.tar.gz
cd kbd-1.15.2

patch -Np1 -i ../kbd-1.15.2-backspace-1.patch

./configure --prefix=/usr --datadir=/lib/kbd

make
make install

mv -v /usr/bin/{kbd_mode,loadkeys,openvt,setfont} /bin

cd ${PACKAGES_DIR}
rm -rf kbd-1.15.2

}

function build_kmod {

cd ${PACKAGES_DIR}
tar xvf kmod-5.tar.xz
cd kmod-5

liblzma_CFLAGS="-I/usr/include" \
liblzma_LIBS="-L/lib -llzma"    \
zlib_CFLAGS="-I/usr/include"    \
zlib_LIBS="-L/lib -lz"          \
./configure --prefix=/usr --bindir=/bin --libdir=/lib --sysconfdir=/etc --with-xz     --with-zlib

make

make pkgconfigdir=/usr/lib/pkgconfig install
for target in depmod insmod modinfo modprobe rmmod; do
  ln -sv ../bin/kmod /sbin/$target
done
ln -sv kmod /bin/lsmod

cd ${PACKAGES_DIR}
rm -rf kmod-5

}

function build_shadow {

cd ${PACKAGES_DIR}
tar xvf shadow-4.1.5.tar.bz2
cd shadow-4.1.5

patch -Np1 -i ../shadow-4.1.5-nscd-1.patch

sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \;

sed -i -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD SHA512@' -e 's@/var/spool/mail@/var/mail@' etc/login.defs

./configure --sysconfdir=/etc

make
make install

mv -v /usr/bin/passwd /bin

cd ${PACKAGES_DIR}
rm -rf shadow-4.1.5

}

function build_sysklogd {

cd ${PACKAGES_DIR}
tar xvf sysklogd-1.5.tar.gz
cd sysklogd-1.5

make
make BINDIR=/sbin install

cd ${PACKAGES_DIR}
rm -rf sysklogd-1.5

}

function configure_sysklogd {

cat > /etc/syslog.conf << "EOF"
# Begin /etc/syslog.conf

auth,authpriv.* -/var/log/auth.log
*.*;auth,authpriv.none -/var/log/sys.log
daemon.* -/var/log/daemon.log
kern.* -/var/log/kern.log
mail.* -/var/log/mail.log
user.* -/var/log/user.log
*.emerg *

# End /etc/syslog.conf
EOF

}

function build_sysvinit {

cd ${PACKAGES_DIR}
tar xvf sysvinit-2.88dsf.tar.bz2
cd sysvinit-2.88dsf

sed -i 's@Sending processes@& configured via /etc/inittab@g' src/init.c

sed -i -e 's/utmpdump wall/utmpdump/' -e '/= mountpoint/d' -e 's/mountpoint.1 wall.1//' src/Makefile

make -C src
make -C src install

cd ${PACKAGES_DIR}
rm -rf sysvinit-2.88dsf

}

function build_udev {

cd ${PACKAGES_DIR}
tar xvf udev-181.tar.xz
cd udev-181

tar -xvf ../udev-config-20100128.tar.bz2

install -dv /lib/{firmware,udev/devices/pts}
mknod -m0666 /lib/udev/devices/null c 1 3

BLKID_CFLAGS="-I/usr/include/blkid"  \
BLKID_LIBS="-L/lib -lblkid"          \
KMOD_CFLAGS="-I/usr/include"         \
KMOD_LIBS="-L/lib -lkmod"            \
./configure  --prefix=/usr           \
             --with-rootprefix=''    \
             --bindir=/sbin          \
             --sysconfdir=/etc       \
             --libexecdir=/lib       \
             --enable-rule_generator \
             --disable-introspection \
             --disable-keymap        \
             --disable-gudev         \
             --with-usb-ids-path=no  \
             --with-pci-ids-path=no  \
             --with-systemdsystemunitdir=no

make
make install

rmdir -v /usr/share/doc/udev

cd udev-config-20100128
make install

cd ${PACKAGES_DIR}
rm -rf udev-181

}

if [ -z "$CXS_BUILDD" ]; then
   setup_dirs
   setup_env
else
   prepare
   create_dirs
   build_linux_headers
   build_glibc
   configure_glibc
   adjust_toolchain
   build_zlib
   build_ncurses
   build_sed
   build_util_linux
   build_psmisc
   build_e2fsprogs
   build_coreutils
   build_iana_etc
   build_bison
   build_procps
   build_grep
   build_readline
   build_bash
   build_libtool
   build_inetutils
   build_findutils
   build_flex
   build_xz
   build_grub
   build_iproute2
   build_kbd
   build_kmod
   build_shadow
   build_sysklogd
   configure_sysklogd
   build_sysvinit
   build_udev
   /bin/bash
fi

