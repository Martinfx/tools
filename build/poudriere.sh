#!/bin/sh

# Copyright (c) 2026 Franco Fichtner <franco@opnsense.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.


set -e

SELF=poudriere

. ./common.sh

if [ -z "$(which poudriere)" ]; then
	echo ">>> Required binary 'poudriere' is not installed." >&2
	echo "To fix this please run 'pkg install poudriere'" >&2
	exit 1
fi

# jail(8) forbids a dot in the name and our settings directory carries one
POUDRIERE_JAIL="${PRODUCT_TYPE}_$(echo ${PRODUCT_SETTINGS} | tr '.' '_')_${PRODUCT_ARCH}"
POUDRIERE_TREE="${PRODUCT_TYPE}"
POUDRIERE_ETC="/usr/local/etc/poudriere.d"
POUDRIERE_LIST="${TARGETDIR}/${SELF}.list"

# poudriere spells a cross build as TARGET.TARGET_ARCH
POUDRIERE_ARCH="${PRODUCT_ARCH}"
if [ "${PRODUCT_TARGET}" != "${PRODUCT_ARCH}" ]; then
	POUDRIERE_ARCH="${PRODUCT_TARGET}.${PRODUCT_ARCH}"
fi

# Resolve ports.conf the way the ports step does, so that a poudriere run
# builds the same set: the origins carry their flavours through unchanged
# and the architecture column drops what this build is not supposed to see.
poudriere_list()
{
	local LIST

	LIST=$(list_packages "${PORTSLIST}" ${CONFIGDIR}/ports.conf)

	echo "${LIST}" > ${POUDRIERE_LIST}

	echo ">>> Wrote $(echo "${LIST}" | wc -l | tr -d ' ') ports to ${POUDRIERE_LIST}"
}

POUDRIERE_USAGE="Use one of: list conf jail ports dry bulk"

if [ -z "${*}" ]; then
	echo ">>> No ${SELF} command given.  ${POUDRIERE_USAGE}" >&2
	exit 1
fi

for ARG in ${@}; do
	case ${ARG} in
	list)
		poudriere_list
		;;
	conf)
		mkdir -p ${POUDRIERE_ETC}

		# The ports step hands these to each port on the command
		# line, which poudriere has no equivalent for, so they go
		# into the jail's make.conf instead.  WRKDIRPREFIX is left
		# out on purpose: poudriere owns the work directories.
		{
			sh ./make.conf.sh | grep -v '^WRKDIRPREFIX='
			echo
			echo "# added by the ${SELF} build step"
			echo "SRC_BASE=		/usr/src"
			echo "PRODUCT_ABI=		${PRODUCT_ABI}"
			echo "PRODUCT_ARCH=		${PRODUCT_ARCH}"
		} > ${POUDRIERE_ETC}/${POUDRIERE_JAIL}-make.conf

		# match the base the images ship rather than a stock one
		cp ${CONFIGDIR}/src.conf \
		    ${POUDRIERE_ETC}/${POUDRIERE_JAIL}-src.conf

		echo ">>> Wrote ${POUDRIERE_ETC}/${POUDRIERE_JAIL}-make.conf"
		echo ">>> Wrote ${POUDRIERE_ETC}/${POUDRIERE_JAIL}-src.conf"
		;;
	jail)
		# no -b: the tree is expected to be built already, so this
		# installs out of the object directory that base left behind
		# rather than compiling the world a second time, and the
		# version is read from the tree's own newvers.sh
		if poudriere jail -i -j ${POUDRIERE_JAIL} > /dev/null 2>&1; then
			poudriere jail -u -j ${POUDRIERE_JAIL}
		else
			poudriere jail -c -j ${POUDRIERE_JAIL} \
			    -a ${POUDRIERE_ARCH} -m src=${SRCDIR}
		fi
		;;
	ports)
		# null-mounted: the tree stays under our own git control
		if poudriere ports -l -q | awk '{ print $1 }' | \
		    grep -qx ${POUDRIERE_TREE}; then
			echo ">>> Reusing ports tree ${POUDRIERE_TREE}"
		else
			poudriere ports -c -p ${POUDRIERE_TREE} -m null \
			    -M ${PORTSDIR}
		fi
		;;
	bulk|dry)
		POUDRIERE_DRY=
		if [ ${ARG} = "dry" ]; then
			POUDRIERE_DRY=-n
		fi

		# regenerate so that a run always matches the config as it
		# stands right now and not whatever was listed last time
		poudriere_list

		poudriere bulk ${POUDRIERE_DRY} -j ${POUDRIERE_JAIL} \
		    -p ${POUDRIERE_TREE} -J ${CPUS} -f ${POUDRIERE_LIST}
		;;
	*)
		echo ">>> Unknown ${SELF} command: ${ARG}" >&2
		echo "${POUDRIERE_USAGE}" >&2
		exit 1
		;;
	esac
done
