#!/bin/bash
#set -x
#set -e

thisdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# we take 2 arguments
# first arg is the directory of the application we're adding python support to
# second arg is where to install dependencies; cppyy packages / ROOT
if [ $# -lt 1 ]; then
	echo "usage: $0 [directory of parent application] [installation directory=${thisdir}]"
	exit 1
fi

ToolAppPath=$1
# check the given directory exists and is writable
if [ ! -d ${ToolAppPath} ] || [ ! -w ${ToolAppPath} ]; then
	echo "Application directory ${ToolAppPath} is not present or is not writable!"
	exit 1
fi

INSTALLDIR="$thisdir"
if [ $# -gt 1 ]; then
	INSTALLDIR="$2"
fi

# perform installation of cppyy (or ROOT, which has cppyy internally)
echo "Calling installer script for dependencies"
#${thisdir}/Install.sh ${INSTALLDIR} ${ToolAppPath}
${thisdir}/Install_root.sh ${INSTALLDIR} ${ToolAppPath}
if [ $? -ne 0 ]; then
	echo "Install script returned an error, aborting"
	exit 1
fi

exit 0

# Bonus material: we can support mixing c++ and python via the PythonScript wrapper

cp ${thisdir}/PythonScript.cpp ${ToolAppPath}/src
cp ${thisdir}/PythonScript.h ${ToolAppPath}/include

# the Python API (Python.h) contains a lot of instances of 'long long', which
# technically is not part of the c++ standard. With the '-pedantic' flag, g++
# will output a slew of warnings to this effect, so let's silence them.
if [ `grep -q CXXFLAGS ${ToolAppPath}/Makefile` -eq 0 ]; then
	# append to the CXXFLAGS if they are already defined...
	sed -i '/^CXXFLAGS=.*/a CXXFLAGS += -Wno-long-long' ${ToolAppPath}/Makefile
else
	# otherwise insert them at the start of the Makefile
	sed -i '1 i\CXXFLAGS=-Wno-long-long' ${ToolAppPath}/Makefile
fi

# add python includes and libraries to the Makefile
# FIXME do this better for standalone Makefile: define PythonInclude and PythonLib Makefile variables
# and then add them to the flags for appropriate targets.
# for now we just hijack ToolDAQInclude and ToolDAQLib
sed -i '/ToolDAQInclude =.*/a ToolDAQInclude += `python3-config --cflags`' ${ToolAppPath}/Makefile
# for python3.8+ we need to add `--embed` to `--libs` or `--ldflags` to get `-lpython3.*`
# Using `--ldflags` includes the lib directory `-L/..` as well as the libraries `-l..`
LIBFLAGS=$(python3-config --ldflags --embed &>/dev/null && echo "python3-config --ldflags --embed" || echo "python3-config --ldflags")
LIBLINE='ToolDAQLib += `'"${LIBFLAGS}"'`'
awk -i inplace -v "var=${LIBLINE}" '{print} /ToolDAQLib/ && !x {print var; x=1}' ${ToolAppPath}/Makefile

exit 0
