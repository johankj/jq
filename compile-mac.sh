#!/usr/bin/env bash
# compile-mac.sh based on compile-ios.sh

# Defaults
set -e
oniguruma='6.9.3'

unset CFLAGS
unset CXXFLAGS
unset LDFLAGS

# Parse args. 
usage(){
cat << EOF
${0##*/}: usage

    Description:
       This simple script builds oniguruma and jq for macOS devices.

    Arguments:
    --extra-cflags <arg>: Pass defines or includes to clang.
    --extra-ldflags <arg>: Pass libs or includes to ld64.

    --with-oniguruma <arg>: Change default version of onigurma from ${oniguruma}.
EOF
exit 1
}

while (( $# )); do
   case "$1" in
      --with-oniguruma) shift; oniguruma="${1}" ;;

      --extra-cflags) shift; export CFLAGS_="${1}" ;;
      --extra-ldflags) shift; export LDFLAGS_="${1}" ;;

      --help) usage ;;
      *) echo -e "Unknown option: ${1}\n"; usage ;;
   esac
   shift
done 

# Start building.
echo "Building..."
MAKEJOBS="$(sysctl -n hw.ncpu || echo 1)"
CC_="$(xcrun -f clang || echo clang)"

onig_url="https://github.com/kkos/oniguruma/releases/download/v${oniguruma}/onig-${oniguruma}.tar.gz"
builddir="${TMPDIR:-/tmp}/${RANDOM:-'xxxxx'}-compile-ios-build"
cwd="$(realpath ${PWD} 2>/dev/null || echo ${PWD})"

t_exit() {
cat << EOF

A error as occured.
    oniguruma location: ${builddir}/onig/onig-${oniguruma}
    jq location: ${cwd}

    Provide config.log and console logs when posting a issue.

EOF
}
trap t_exit ERR

#  Onig.
mkdir -p "${builddir}/onig"
cd "${builddir}/"
curl -L ${onig_url} | tar xz
for arch in x86_64 arm64; do
  SYSROOT=$(xcrun -f --sdk macosx --show-sdk-path)
  HOST="${arch}-apple-darwin"
  [[ "${arch}" = "arm64" ]] && HOST="aarch64-apple-darwin"

  CFLAGS="-arch ${arch} -isysroot ${SYSROOT} ${CFLAGS_} -D_REENTRANT"
  LDFLAGS="-arch ${arch} -isysroot ${SYSROOT} ${LDFLAGS_}"
  CC="${CC_} ${CFLAGS}"

  # ./configure; make install
  cd "${builddir}/onig-${oniguruma}"
  MACOSX_DEPLOYMENT_TARGET=11.0 CC=${CC} LDFLAGS=${LDFLAGS} \
  ./configure --host=${HOST} --build=$(./config.guess) --enable-shared=no --enable-static=yes --enable-all-static --prefix=/
  make -j${MAKEJOBS} install DESTDIR="${cwd}/mac/onig/${arch}"
  make clean

  # Jump back to JQ.
  cd ${cwd}
  [[ ! -f ./configure ]] && autoreconf -ivf
  MACOSX_DEPLOYMENT_TARGET=11.0 CC=${CC} LDFLAGS=${LDFLAGS} \
  ./configure --host=${HOST} --build=$(./config/config.guess) --enable-docs=no --enable-shared=no --enable-static=yes --enable-all-static --prefix=/ --with-oniguruma=${cwd}/mac/onig/${arch} $(test -z ${BISON+x} && echo '--disable-maintainer-mode')
  make -j${MAKEJOBS} install DESTDIR="${cwd}/mac/jq/${arch}"
  make clean

  # Merge libjq.a and libonig.a into a single static library: libjqonig.a
  mkdir -p "${cwd}/mac/jqonig/${arch}/lib"
  libtool -static -o "${cwd}/mac/jqonig/${arch}/lib/libjqonig.a" "${cwd}/mac/jq/${arch}/lib/libjq.a" "${cwd}/mac/onig/${arch}/lib/libonig.a"
done

mkdir -p "${cwd}/mac/dest/lib"
# lipo, make a universal static lib.
# lipo -create -output ${cwd}/mac/dest/lib/libonig.a ${cwd}/mac/onig/{x86_64,arm64}/lib/libonig.a
# lipo -create -output ${cwd}/mac/dest/lib/libjq.a ${cwd}/mac/jq/{x86_64,arm64}/lib/libjq.a
lipo -create -output ${cwd}/mac/dest/lib/libjqonig.a ${cwd}/mac/jqonig/{x86_64,arm64}/lib/libjqonig.a

# Take the x86_64 headers- the most common target.
cp -r ${cwd}/mac/jq/x86_64/include ${cwd}/mac/dest/
rm -rf ${cwd}/build/mac/{x86_64,arm64}

# Strip debug symbols from libraries
find ${cwd}/mac -iname '*.a' | xargs strip -S

echo "Output to ${cwd}/mac/dest"
