#!/bin/bash

# Setup the environment
function setup_env {

env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' CXS_BUILD=1 ${0}

}

function prepare {

set +h
umask 022
HOME_DIR=$(pwd)
LFS=$HOME_DIR/cxs-baseware
PACKAGES_DIR=$LFS/packages/
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
FORCE_UNSAFE_CONFIGURE=1
export LFS LC_ALL LFS_TGT PATH FORCE_UNSAFE_CONFIGURE

sudo mkdir -v $LFS/tools
sudo ln -sv $LFS/tools /

}

#
# Making temp system
#

# Binutils 2.22 (pass 1)
function build_binutils_pass1 {

cd $PACKAGES_DIR
tar xvf binutils-2.22.tar.bz2
cd binutils-2.22
mkdir -v ../binutils-build
cd ../binutils-build
../binutils-2.22/configure --target=${LFS_TGT} --prefix=/tools --disable-nls --disable-werror
make
case $(uname -m) in
  x86_64) mkdir -v /tools/lib && ln -sv lib /tools/lib64 ;;
esac
make install
cd $PACKAGES_DIR
rm -rf binutils-2.22
rm -rf binutils-build

}

# GCC 4.6.2 (pass 1)
function build_gcc_pass1 {

cd $PACKAGES_DIR
tar xvf gcc-4.6.2.tar.bz2
cd gcc-4.6.2
tar -jxf ../mpfr-3.1.0.tar.bz2
mv -v mpfr-3.1.0 mpfr
tar -Jxf ../gmp-5.0.4.tar.xz
mv -v gmp-5.0.4 gmp
tar -zxf ../mpc-0.9.tar.gz
mv -v mpc-0.9 mpc
patch -Np1 -i ../gcc-4.6.2-cross_compile-1.patch
mkdir -v ../gcc-build
cd ../gcc-build
../gcc-4.6.2/configure --target=${LFS_TGT} --prefix=/tools --disable-nls --disable-shared --disable-multilib --disable-decimal-float --disable-threads --disable-libmudflap --disable-libssp --disable-libgomp --disable-libquadmath --disable-target-libiberty --disable-target-zlib --enable-languages=c --without-ppl --without-cloog --with-mpfr-include=$(pwd)/../gcc-4.6.2/mpfr/src --with-mpfr-lib=$(pwd)/mpfr/src/.libs
make
make install
ln -vs libgcc.a `${LFS_TGT}-gcc -print-libgcc-file-name | \
    sed 's/libgcc/&_eh/'`
cd $PACKAGES_DIR
rm -rf gcc-4.6.2
rm -rf gcc-build

}

function copy_linux_headers {

cd $PACKAGES_DIR
tar xvf linux-3.2.6.tar.xz
cd linux-3.2.6
make mrproper
make headers_check
make INSTALL_HDR_PATH=dest headers_install
cp -rv dest/include/* /tools/include
cd $PACKAGES_DIR
rm -rf linux-3.2.6

}

function build_glibc_pass1 {

cd $PACKAGES_DIR
tar xvf glibc-2.14.1.tar.bz2
cd glibc-2.14.1
patch -Np1 -i ../glibc-2.14.1-gcc_fix-1.patch
patch -Np1 -i ../glibc-2.14.1-cpuid-1.patch
mkdir -v ../glibc-build
cd ../glibc-build
case `uname -m` in
  i?86) echo "CFLAGS += -march=i486 -mtune=native" > configparms ;;
esac
../glibc-2.14.1/configure --prefix=/tools --host=${LFS_TGT} --build=$(../glibc-2.14.1/scripts/config.guess) --disable-profile --enable-add-ons --enable-kernel=2.6.25 --with-headers=/tools/include libc_cv_forced_unwind=yes libc_cv_c_cleanup=yes
make
make install

}

function adjust_toolchain {

SPECS=`dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/specs
$LFS_TGT-gcc -dumpspecs | sed \
  -e 's@/lib\(64\)\?/ld@/tools&@g' \
  -e "/^\*cpp:$/{n;s,$, -isystem /tools/include,}" > $SPECS 
echo "New specs file is: $SPECS"
unset SPECS

}

function test_toolchain {

echo 'main(){}' > dummy.c
$LFS_TGT-gcc -B/tools/lib dummy.c
readelf -l a.out | grep ': /tools'
rm -v dummy.c a.out

}

function build_binutils_pass2 {

cd $PACKAGES_DIR
tar xvf binutils-2.22.tar.bz2
cd binutils-2.22
mkdir -v ../binutils-build
cd ../binutils-build
CC="$LFS_TGT-gcc -B/tools/lib/" AR=$LFS_TGT-ar RANLIB=$LFS_TGT-ranlib ../binutils-2.22/configure --prefix=/tools --disable-nls --with-lib-path=/tools/lib
make
make install
make -C ld clean
make -C ld LIB_PATH=/usr/lib:/lib
cp -v ld/ld-new /tools/bin

}

function build_gcc_pass2 {

cd $PACKAGES_DIR
tar xvf gcc-4.6.2.tar.bz2
cd gcc-4.6.2
patch -Np1 -i ../gcc-4.6.2-startfiles_fix-1.patch
cp -v gcc/Makefile.in{,.orig}
sed 's@\./fixinc\.sh@-c true@' gcc/Makefile.in.orig > gcc/Makefile.in
cp -v gcc/Makefile.in{,.tmp}
sed 's/^T_CFLAGS =$/& -fomit-frame-pointer/' gcc/Makefile.in.tmp > gcc/Makefile.in
for file in $(find gcc/config -name linux64.h -o -name linux.h -o -name sysv4.h)
do
  cp -uv $file{,.orig}
  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' -e 's@/usr@/tools@g' $file.orig > $file
  echo '
#undef STANDARD_INCLUDE_DIR
#define STANDARD_INCLUDE_DIR 0
#define STANDARD_STARTFILE_PREFIX_1 ""
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
  touch $file.orig
done
case $(uname -m) in
  x86_64)
    for file in $(find gcc/config -name t-linux64) ; do \
      cp -v $file{,.orig}
      sed '/MULTILIB_OSDIRNAMES/d' $file.orig > $file
    done
  ;;
esac
tar -jxf ../mpfr-3.1.0.tar.bz2
mv -v mpfr-3.1.0 mpfr
tar -Jxf ../gmp-5.0.4.tar.xz
mv -v gmp-5.0.4 gmp
tar -zxf ../mpc-0.9.tar.gz
mv -v mpc-0.9 mpc
mkdir -v ../gcc-build
cd ../gcc-build
CC="$LFS_TGT-gcc -B/tools/lib/" AR=$LFS_TGT-ar RANLIB=$LFS_TGT-ranlib ../gcc-4.6.2/configure --prefix=/tools --with-local-prefix=/tools --enable-clocale=gnu --enable-shared --enable-threads=posix --enable-__cxa_atexit --enable-languages=c,c++ --disable-libstdcxx-pch --disable-multilib --disable-bootstrap --disable-libgomp --without-ppl --without-cloog --with-mpfr-include=$(pwd)/../gcc-4.6.2/mpfr/src --with-mpfr-lib=$(pwd)/mpfr/src/.libs
make
make install
ln -vs gcc /tools/bin/cc
cd $PACKAGES_DIR
rm -rf gcc-4.6.2

}

function build_tcl {

cd $PACKAGES_DIR
tar xvf tcl8.5.11-src.tar.gz
cd tcl8.5.11
cd unix
./configure --prefix=/tools
make
make install
chmod -v u+w /tools/lib/libtcl8.5.so
make install-private-headers
ln -sv tclsh8.5 /tools/bin/tclsh
cd $PACKAGES_DIR
rm -rf tcl8.5.11

}

function build_expect {

cd $PACKAGES_DIR
tar xvf expect5.45.tar.gz
cd expect5.45
cp -v configure{,.orig}
sed 's:/usr/local/bin:/bin:' configure.orig > configure
./configure --prefix=/tools --with-tcl=/tools/lib --with-tclinclude=/tools/include
make
make SCRIPTS="" install
cd $PACKAGES_DIR
rm -rf expect5.45

}

function build_dejagnu {

cd $PACKAGES_DIR
tar xvf dejagnu-1.5.tar.gz
cd dejagnu-1.5
./configure --prefix=/tools
make install
cd $PACKAGES_DIR
rm -rf dejagnu-1.5

}

function build_check {

cd $PACKAGES_DIR
tar xvf check-0.9.8.tar.gz
cd check-0.9.8
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf check-0.9.8

}

function build_ncurses {

cd $PACKAGES_DIR
tar xvf ncurses-5.9.tar.gz
cd ncurses-5.9
./configure --prefix=/tools --with-shared --without-debug --without-ada --enable-overwrite
make
make install
cd $PACKAGES_DIR
rm -rf ncurses-5.9

}

function build_bash {

cd $PACKAGES_DIR
tar xvf bash-4.2.tar.gz
cd bash-4.2
patch -Np1 -i ../bash-4.2-fixes-4.patch
./configure --prefix=/tools --without-bash-malloc
make
make install
ln -vs bash /tools/bin/sh
cd $PACKAGES_DIR
rm -rf bash-4.2

}

function build_bzip2 {

cd $PACKAGES_DIR
tar xvf bzip2-1.0.6.tar.gz
cd bzip2-1.0.6
make
make PREFIX=/tools install
cd $PACKAGES_DIR
rm -rf bzip2-1.0.6

}

function build_coreutils {

cd $PACKAGES_DIR
tar xvf coreutils-8.15.tar.xz
cd coreutils-8.15
./configure --prefix=/tools --enable-install-program=hostname
make
make install
cp -v src/su /tools/bin/su-tools
cd $PACKAGES_DIR
rm -rf coreutils-8.15

}

function build_diffutils {

cd $PACKAGES_DIR
tar xvf diffutils-3.2.tar.gz
cd diffutils-3.2
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf diffutils-3.2

}

function build_file {

cd $PACKAGES_DIR
tar xvf file-5.10.tar.gz
cd file-5.10
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf file-5.10

}

function build_findutils {

cd $PACKAGES_DIR
tar xvf findutils-4.4.2.tar.gz
cd findutils-4.4.2
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf findutils-4.4.2

}

function build_gawk
{

cd $PACKAGES_DIR
tar xvf gawk-4.0.0.tar.bz2
cd gawk-4.0.0
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf gawk-4.0.0

}

function build_gettext {

cd $PACKAGES_DIR
tar xvf gettext-0.18.1.1.tar.gz
cd gettext-0.18.1.1
cd gettext-tools
./configure --prefix=/tools --disable-shared
make -C gnulib-lib
make -C src msgfmt
cp -v src/msgfmt /tools/bin
cd $PACKAGES_DIR
rm -rf gettext-0.18.1.1

}

function build_grep {

cd $PACKAGES_DIR
tar xvf grep-2.10.tar.xz
cd grep-2.10
./configure --prefix=/tools --disable-perl-regexp
make
make install
cd $PACKAGES_DIR
rm -rf grep-2.10

}

function build_gzip {

cd $PACKAGES_DIR
tar xvf gzip-1.4.tar.gz
cd gzip-1.4
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf gzip-1.4

}

function build_m4 {

cd $PACKAGES_DIR
tar xvf m4-1.4.16.tar.bz2
cd m4-1.4.16
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf m4-1.4.16

}

function build_make {

cd $PACKAGES_DIR
tar xvf make-3.82.tar.bz2
cd make-3.82
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf make-3.82

}

function build_patch {

cd $PACKAGES_DIR
tar xvf patch-2.6.1.tar.bz2
cd patch-2.6.1
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf patch-2.6.1

}

function build_perl {

cd $PACKAGES_DIR
tar xvf perl-5.14.2.tar.bz2
cd perl-5.14.2
patch -Np1 -i ../perl-5.14.2-libc-1.patch
sh Configure -des -Dprefix=/tools
make
cp -v perl cpan/podlators/pod2man /tools/bin
mkdir -pv /tools/lib/perl5/5.14.2
cp -Rv lib/* /tools/lib/perl5/5.14.2
cd $PACKAGES_DIR
rm -rf perl-5.14.2

}

function build_sed {

cd $PACKAGES_DIR
tar xvf sed-4.2.1.tar.bz2
cd sed-4.2.1
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf sed-4.2.1

}

function build_tar {

cd $PACKAGES_DIR
tar xvf tar-1.26.tar.bz2
cd tar-1.26
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf tar-1.26

}

function build_texinfo {

cd $PACKAGES_DIR
tar xvf texinfo-4.13a.tar.gz
cd texinfo-4.13
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf texinfo-4.13

}

function build_xz {

cd $PACKAGES_DIR
tar xvf xz-5.0.3.tar.bz2
cd xz-5.0.3
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf xz-5.0.3

}

function build_autoconf {

cd $PACKAGES_DIR
tar xvf autoconf-2.68.tar.bz2
cd autoconf-2.68
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf autoconf-2.68

}

function build_automake {

cd $PACKAGES_DIR
tar xvf automake-1.11.3.tar.xz
cd automake-1.11.3
./configure --prefix=/tools
make
make install
cd $PACKAGES_DIR
rm -rf automake-1.11.3

}

function strip_symbols {

strip --strip-debug /tools/lib/*
strip --strip-unneeded /tools/{,s}bin/*
rm -rf /tools/{,share}/{info,man,doc}

}

function setup_dirs {

sudo mkdir -v $LFS/{dev,proc,sys}
sudo mknod -m 600 $LFS/dev/console c 5 1
sudo mknod -m 666 $LFS/dev/null c 1 3
sudo mount -v --bind /dev $LFS/dev
sudo mount -vt devpts devpts $LFS/dev/pts
sudo mount -vt tmpfs shm $LFS/dev/shm
sudo mount -vt proc proc $LFS/proc
sudo mount -vt sysfs sysfs $LFS/sys

}

CMD_LINE=${0}

if [ -z "$CXS_BUILD" ]; then
   setup_env ${CMD_LINE}
else
   prepare
   build_binutils_pass1
   build_gcc_pass1
   copy_linux_headers
   build_glibc_pass1
   adjust_toolchain
   test_toolchain
   build_binutils_pass2
   build_gcc_pass2
   build_tcl
   build_expect
   build_dejagnu
   build_check
   build_ncurses
   build_bash
   build_bzip2
   build_coreutils
   build_diffutils
   build_file
   build_findutils
   build_gawk
   build_gettext
   build_grep
   build_gzip
   build_m4
   build_make
   build_patch
   build_perl
   build_sed
   build_tar
   build_texinfo
   build_xz
   build_autoconf
   build_automake
   strip_symbols
   setup_dirs
fi


