#!/bin/bash
set -x
prog=dm
extern=.extern
DFLAGS="-w -g -O"

build_tinyendian() {
    pushd ${extern}
        [ ! -d "tinyendian" ] && git clone --recursive https://github.com/dlang-community/tinyendian
        pushd tinyendian
            if [[ $(find . -name '*.a') ]]; then
                popd
                popd
                return
            fi
            git checkout v0.2.0
            dmd ${DFLAGS} -lib -oflibtinyendian.a \
                $(find source -type f -name '*.d')
        popd
    popd
}

build_dyaml() {
    pushd ${extern}
        [ ! -d "D-YAML" ] && git clone --recursive https://github.com/dlang-community/D-YAML
        pushd D-YAML
            if [[ $(find . -name '*.a') ]]; then
                popd
                popd
                return
            fi
            git checkout v0.7.1
            dmd ${DFLAGS} -lib -oflibdyaml.a \
                -I../tinyendian/source \
                ../tinyendian/libtinyendian.a \
                $(find source -type f -name '*.d')
        popd
    popd
}

clean() {
    rm -rf ${extern}
    rm -rf *.o
}

if [ "$1" == "clean" ]; then
    clean
    exit 0
fi

mkdir -p ${extern}
build_tinyendian
build_dyaml
dmd ${DFLAGS} -of${prog} \
    -I${extern}/tinyendian/source \
    -I${extern}/D-YAML/source \
    ${extern}/D-YAML/libdyaml.a \
    $(find source -type f -name '*.d')
