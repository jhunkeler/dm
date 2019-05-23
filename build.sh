#!/bin/bash
set -x
prog=dm
extern=.extern
DFLAGS="-w -g -O"

build_tinyendian() {
    pushd ${extern}
        git clone --recursive https://github.com/dlang-community/tinyendian
        pushd tinyendian
            git checkout v0.2.0
            dmd ${DFLAGS} -lib -oflibtinyendian.a \
                $(find source -type f -name '*.d')
        popd
    popd
}

build_dyaml() {
    pushd ${extern}
        git clone --recursive https://github.com/dlang-community/D-YAML
        pushd D-YAML
            git checkout v0.7.1
            dmd ${DFLAGS} -lib -oflibdyaml.a \
                -I../tinyendian/source \
                ../tinyendian/libtinyendian.a \
                $(find source -type f -name '*.d')
        popd
    popd
}


mkdir -p ${extern}
build_tinyendian
build_dyaml
dmd ${DFLAGS} -of${prog} \
    -I${extern}/tinyendian/source \
    -I${extern}/D-YAML/source \
    ${extern}/D-YAML/libdyaml.a \
    $(find source -type f -name '*.d')
