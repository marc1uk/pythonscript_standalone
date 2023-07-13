#!/bin/bash
set -x
#set -e

# a function to check for presence of cppyy. New ROOT versions come with it.
# XXX for some reason this doesn't like the use of tab for whitespace!!! XXX
checkcppyy(){
    # a quick test, also trigger rebuilding of the pch
    echo "the following test should print 0·1·2·3·4·5·6·7·8·9¶"
    # especially no indents here or python complains
    PYCMDS="
import cppyy
from cppyy.gbl.std import vector
v = vector[int](range(10))
for m in v: print(m, end=' ')
"
    RESULT=$(echo "${PYCMDS}" | python3)
    
    # we need to do it twice as the first time it prints out a message about recompiling the header
    RESULT=$(echo "${PYCMDS}" | python3)
    
    # trim whitespace
    RESULT="$(echo -n ${RESULT} | xargs echo -n)"
    echo $RESULT | sed 's/ /·/g;s/\t/￫/g;s/\r/§/g;s/$/¶/g'  # check whitespace
    if [ "$RESULT" != "0 1 2 3 4 5 6 7 8 9" ]; then
        echo "Test Failed! Check your installation of python3 and cppyy!"
        return 1
    else
        echo "Test Passed"
        return 0
    fi
}

echo "checking for pre-existing presence of cppyy"
checkcppyy
if [ $? -eq 0 ]; then
	# if we already have it, we have nothing to do....
	# TODO the PythonScript c++ interface may require at least python3-devel as well...?
	echo "cppyy already installed."
	exit 0
fi

CURDIR=${PWD}  # in case we need to return to it. unused.
cd "$( dirname "${BASH_SOURCE[0]}" )"

# first argument is installation destination
INSTALLDIR="/opt"
if [ $# -gt 0 ]; then
	INSTALLDIR="$1"
fi
# check the installation folder exists and is writable
if [ ! -d ${INSTALLDIR} ] || [ ! -w ${INSTALLDIR} ]; then
	# doesn't exist or isn't writable (perhaps an immutable container?)
	echo "Installation directory ${INSTALLDIR} is not present or is not writable!"
	exit 1
fi

# first determine what kind of OS we're on.
REDHATLIKE=$(yum --version >/dev/null 2>&1; echo $?)
DEBIANLIKE=$(dpkg --version >/dev/null 2>&1; echo $?)
NEEDDEPS=""
if [ ${REDHATLIKE} -eq 0 ]; then
	echo "red-hat based OS"
	# red-hat based OS.
	# trigger yum to update its metadata
	echo "updating yum metadata..."
	yum list installed >/dev/null 2>&1
	DEPS=(gcc-c++ gcc make cmake git python3 python3-libs python3-devel python3-pip patch which)
	for DEP in "${DEPS[@]}"; do
		echo "looking for ${DEP}..."
		# this is probably not a great check as 'grep' could match on anything
		# e.g. some python3 add-on, even if python3 is installed, but it'll do.
		# XXX moreover, it will NOT find things like 'rh-python38-python-libs.x86_64'
		# as would be the case if python-3.8 is installed via epel repos, or somesuch
		GOTDEP=$(yum list installed 2>/dev/null | grep "${DEP}" >/dev/null 2>&1; echo $?)
		if [ ${GOTDEP} -ne 0 ]; then
			echo "not found"
			NEEDDEPS="${NEEDDEPS} ${DEP}"
		fi
	done
elif [ ${DEBIANLIKE} -eq 0 ]; then
	echo "debian based OS"
	DEPS=(gcc g++ make cmake git libpython3 python3-dev python3-pip patch debian-utils)
	# per 'dpkg -S $(readlink `which which`)', which is provided by debian-utils, at least in debian.
	for DEP in "${DEPS[@]}"; do
		echo "looking for ${DEP}..."
		GOTDEP=$(dpkg --list | grep "${DEP}" >/dev/null 2>&1; echo $?)
		if [ ${GOTDEP} -ne 0 ]; then
			echo "not found"
			NEEDDEPS="${NEEDDEPS} ${DEP}"
		fi
	done
else
	# can't recognise the system to check what's installed, or install if necessary...
	# ask the user if they want to continue under the assumption we have everything
	echo "Python tools require the following system dependencies:"
	echo "gcc-c++ >4.8 gcc make cmake git python3 python3-libs python3-devel python3-pip which"
	echo "If all of these packages are installed, enter 1 to continue to attempt installation"
	echo "Otherwise enter 2 to abort and re-run this script once those dependencies are installed"
	select result in Continue Abort; do
		if [ "$result" == "Continue" ] || [ "$result" == "Abort" ]; then
			if [ "$result" == "Abort" ]; then
				echo "terminating.";
				exit 1;
			else
				echo "Attempting installation assuming dependencies are installed";
				NEEDDEPS=""
				break;
			fi
		else
			echo "please enter 1 or 2";
		fi
	done
fi

# if we have a pre-existing g++ install, check the version is >4.9 (required to build cppyy)
if [ $(which g++ &> /dev/null; echo $?) -eq 0 ]; then
	GCCVER=$(g++ -dumpversion)
	GCCOK=$(echo -e "4.9\n${GCCVER}" | sort -V -C; echo $?)
	if [ ${GCCOK} -ne 0 ]; then
		# installing multiple g++ versions is usually tricky, so let's leave that to the user.
		echo "Your g++ version is not sufficient to build cppyy!"
		echo "please install g++ 4.9 or newer and retry"
		exit 1
	fi
fi

if [ -z "${NEEDDEPS}" ]; then
	echo "All system dependencies satisfied, continuing"
else
	echo "The following system dependencies were not found on your system"
	echo "${NEEDDEPS}"
	# if we're run as root, offer to install them
	if [ "$(whoami)" == "root" ]; then
		echo "Install these packages?"
		select result in No Yes; do
			if [ "$result" == "Yes" ] || [ "$result" == "No" ]; then
				if [ "$result" == "No" ]; then
					echo "It is possible the dependencies are installed and were not detected by the scan. "
					echo -n "If this is the case, and you wish to continue with installation, enter 1. "
					echo "Otherwise to abort installation, enter 2."
					select result in Continue Abort; do
						if [ "$result" == "Continue" ] || [ "$result" == "Abort" ]; then
							if [ "$result" == "Abort" ]; then
								echo "terminating.";
								exit 1;
							else
								echo "Attempting installation assuming dependencies are installed"
								NEEDDEPS=""
								break;
							fi
						else
							echo "please enter 1 or 2";
						fi
					done
					if [ -z "${NEEDDEPS}" ]; then break; fi
				else
					echo "Installing dependencies..."
					if [ ${REDHATLIKE} -eq 0 ]; then
						yum install -y ${NEEDDEPS}
						INSTALLOK=$?
					elif [ ${DEBIANLIKE} -eq 0 ]; then
						apt-get install -y ${NEEDDEPS}
						INSTALLOK=$?
					fi
					if [ ${INSTALLOK} -ne 0 ]; then
						echo "Errors encountered; please install dependencies manually" \
						     " and re-run this script"
						exit 1;
					else
						echo "Dependencies installed successfully"
						break;
					fi
				fi
			else
				echo "please enter 1 or 2";
			fi
		done
	else
		# we need dependencies but we're not root so can't install them
		echo "Please re-run this script as root, or install these packages manually and re-run this script"
		exit 1;
	fi
fi

# XXX TODO replace all this user-directory nonsense with
# --prefix, --root or --target
# see https://www.mankier.com/1/pip-install

# See if there's a 'tooluser' user, which should be present on ToolFramework-based containers
USERVALID=`id -u "tooluser" &> /dev/null; echo $?`
if [ "${USERVALID}" -eq 0 ]; then
	TOOLUSER="tooluser"
fi

# find out who is invoking this script
THISUSER=$(whoami)
# if the current user is root, try to identify an
# underlying user calling this script with `sudo`
# (pip recommends not installing as root)
if [ "${THISUSER}" == "root" ]; then
	if [ ! -z "${SUDO_USER}" ]; then
		THISUSER="${SUDO_USER}"
	elif [ $(logname 1>/dev/null 2>&1; echo $?) -eq 0 ]; then
		THISUSER="$(logname)"
	fi
	# note both of these can fail if e.g. you're in a container
	# run with `sudo singularity shell --cleanenv`
fi

# if the user wants to install pip dependencies into another account
# we'll need sudo
GOTSUDO=`which sudo > /dev/null 2>&1; echo $?`
SUDOCMD=""
if [ ${GOTSUDO} -eq 1 ] && [ "$(whoami)" != "root" ]; then
	SUDOCMD="sudo "
fi

# seems like we also need to be root to pip install system-wide
OPTIONS="${THISUSER}"
if [ ${GOTSUDO} -eq 0 ] || [ "$(whoami)" == "root" ]; then
	OPTIONS="System ${OPTIONS}"
fi
if [ ${GOTSUDO} -eq 0 ]; then
	OPTIONS="${OPTIONS} ${TOOLUSER} Other"
fi
OPTIONS="${OPTIONS} Abort"

# ask the user where they want to install pip packages
echo "Where would you like to install pip packages?"
select result in ${OPTIONS}; do
	if [ "$result" == "System" ] || [ "$result" == "${THISUSER}" ] || [ "$result" == "${TOOLUSER}" ] || [ "$result" == "Other" ] || [ "$result" == "Abort" ]; then
		if [ "$result" == "Abort" ]; then
			echo "Aborting"
			exit 1;
		elif [ "$result" == "System" ]; then
			unset PIPFLAGS
			unset SUDOFLAGS
			break;
		elif [ "${result}" == "${THISUSER}" ]; then
			PIPFLAGS="--user"
			if [ "${THISUSER}" == "$(whoami)" ]; then
				unset SUDOFLAGS
			fi
			break;
		elif [ "${result}" == "${TOOLUSER}" ]; then
			THISUSER=${TOOLUSER}
			PIPFLAGS="--user"
			SUDOFLAGS="sudo -u ${THISUSER} -E"
			break;
		else
			echo "enter the user whose home directory you would like to install cppyy into"
			read THISUSER
			USERVALID=`id -u ${THISUSER} &> /dev/null; echo $?`
			if [ "${USERVALID}" -ne 0 ]; then
				echo "unrecognised user"
			else
				PIPFLAGS=" --user"
				SUDOFLAGS="sudo -u ${THISUSER} -E"
				break;
			fi
		fi
	else
		echo "please enter a number corresponding to the desired user or action";
	fi
done

if [ "${PIPFLAGS}" == "--user" ]; then
	echo "pip packages will be installed into home directory of user ${THISUSER}"
else
	echo "pip packages will be installed system-wide"
fi
echo "Proceed?"
select result in Proceed Abort; do
	if [ "$result" == "Proceed" ] || [ "$result" == "Abort" ]; then
		if [ "$result" == "Abort" ]; then
			echo "terminating.";
			exit 1;
		else
			break;
		fi
	else
		echo "please enter 1 or 2";
	fi
done

set -e
#set -x

# make home directory of desired user if it doesn't exist
if [ "${PIPFLAGS}" == "--user" ] && [ ! -d /home/${THISUSER} ]; then
	echo "making home directory for user ${THISUSER}"
	$SUDOCMD mkdir -p /home/${THISUSER}
	chown -R `id -u ${THISUSER}` /home/${THISUSER}
fi

# upgrade pip (required for --no-use-pep517 flag)
echo "updating pip"
$SUDOFLAGS python3 -m pip install $PIPFLAGS --upgrade pip
$SUDOFLAGS python3 -m pip install $PIPFLAGS --upgrade pip
# we'll also need wheel, or the CPyCppyy install will fail
$SUDOFLAGS python3 -m pip install $PIPFLAGS wheel

# otherwise we need to install it
echo "failed to find existing (working) cppyy install; install one now?"
select result in Yes No; do
	if [ "$result" == "Yes" ] || [ "$result" == "No" ]; then
		if [ "$result" == "No" ]; then
			echo "terminating.";
			exit 1;
		else
			break;
		fi
	else
		echo "please enter 1 or 2";
	fi
done

# if we got here user said yes: proceed with cppyy installation

# setup installation environment
export STDCXX=11
#export EXTRA_CLING_ARGS='-nocudainc'
export CLING_REBUID_PCH=1
export PATH=/home/${THISUSER}/.local/bin:$PATH

# start installation
cd ${INSTALLDIR}
echo "installing cppyy_backend"
if [ -d cppyy-backend ]; then
	echo "${INSTALLDIR}/cppyy-backend already exists! Overwrite it?"
	select result in Yes No; do
		if [ "$result" == "Yes" ]; then
			rm -rf cppyy-backend
			break;
		elif [ "$result" == "No" ]; then
			break;
		else
			echo "please enter 1 or 2";
		fi
	done
fi
if [ ! -d cppyy-backend ]; then
	mkdir cppyy-backend
	chmod -R 777 cppyy-backend/
	#$SUDOFLAGS git clone https://github.com/wlav/cppyy-backend.git cppyy-backend/
	$SUDOFLAGS git clone https://github.com/ToolFramework/cppyy-backend.git cppyy-backend/
	cd cppyy-backend
	$SUDOFLAGS git checkout -q cppyy-cling-6.25.2
	cd cling
	$SUDOFLAGS python3 setup.py egg_info
	$SUDOFLAGS python3 create_src_directory.py
	$SUDOFLAGS python3 -m pip install . $PIPFLAGS --upgrade
	cd ../clingwrapper
	$SUDOFLAGS python3 -m pip install . $PIPFLAGS --upgrade --no-use-pep517 --no-deps
fi

echo "installing CPyCppyy"
cd ${INSTALLDIR}
if [ -d CPyCppyy ]; then
	echo "${INSTALLDIR}/CPyCppyy already exists! Overwrite it?"
	select result in Yes No; do
		if [ "$result" == "Yes" ]; then
			rm -rf ${INSTALLDIR}/CPyCppyy
			break;
		elif [ "$result" == "No" ]; then
			break;
		else
			echo "please enter 1 or 2";
		fi
	done
fi
if [ ! -d CPyCppyy ]; then
	mkdir CPyCppyy
	chmod -R 777 CPyCppyy
	#$SUDOFLAGS git clone https://github.com/wlav/CPyCppyy.git CPyCppyy
	$SUDOFLAGS git clone https://github.com/ToolFramework/CPyCppyy.git CPyCppyy
	cd CPyCppyy
	git checkout -q CPyCppyy-1.12.8
	$SUDOFLAGS python3 -m pip install . $PIPFLAGS --upgrade --no-use-pep517 --no-deps
fi

echo "installing cppyy"
cd ${INSTALLDIR}
if [ -d cppyy ]; then
	echo "${INSTALLDIR}/cppyy already exists! Overwrite it?"
	select result in Yes No; do
		if [ "$result" == "Yes" ]; then
			rm -rf ${INSTALLDIR}/cppyy
			break;
		elif [ "$result" == "No" ]; then
			break;
		else
			echo "please enter 1 or 2";
		fi
	done
fi
if [ ! -d cppyy ]; then
	mkdir cppyy
	chmod -R 777 cppyy
	#$SUDOFLAGS git clone https://github.com/wlav/cppyy.git cppyy
	$SUDOFLAGS git clone https://github.com/ToolFramework/cppyy.git cppyy
	cd cppyy
	$SUDOFLAGS git checkout -q 9bf3a2f6798066647e05d00d1c1736b453d336d3
	$SUDOFLAGS python3 -m pip install . $PIPFLAGS --upgrade --no-deps --verbose
fi

# get the local user site
#if [ "${PIPFLAGS}" == "--user" ]; then
#	PACKAGEPATH=$(python -m site --user-site)
#else
#	PACKAGEPATH= ????
#fi
PACKAGEPATH=$(python3 -m pip show cppyy_backend | grep 'Location' | cut -d' ' -f 2)
echo "adding ${PACKAGEPATH} to PYTHONPATH"
export PYTHONPATH=${PACKAGEPATH}:$PYTHONPATH

echo "updating cppyy precompiled header"
rm -f ${PACKAGEPATH}/cppyy/allDict.cxx.pch.*

# weird bugfix when installing system-wide:
# for some reason it doesn't copy in a required library,
# and then segfaults when you try to 'import cppyy'
if [ ! -f ${PACKAGEPATH}/cppyy_backend/lib/libcppyy_backend.so ]; then
	THELIB=$(find ${INSTALLDIR}/cppyy-backend -name "libcppyy_backend.so")
	if [ ! -z "${THELIB}" ] && [ -f "${THELIB}" ]; then
		cp ${THELIB} ${PACKAGEPATH}/cppyy_backend/lib/libcppyy_backend.so
	fi
fi

echo "checking installation of cppyy"
checkcppyy
if [ $? -ne 0 ]; then
	echo "Installation failed. Please manually install cppyy."
	exit 1
fi

# otherwise install succeeded
# one last job: add the path to cppyy module to the application Setup.sh
# get the path to the cppyy module
PACKAGEPATH=$(python3 -m pip show cppyy_backend | grep 'Location' | cut -d' ' -f 2)

# application dir should be second arg
APPDIR="/web"
if [ $# -gt 1 ]; then
	APPDIR=$2
fi
# check the Setup.sh script is found and is writable
if [ -z ${APPDIR} ] || [ ! -w ${APPDIR}/Setup.sh ]; then
	echo "${APPDIR}/Setup.sh not found or not writable!"
	echo "Please add 'export PYTHONPATH=${PACKAGEPATH}:${APPDIR}:\$PYTHONPATH' to this script manually"
	exit 0
fi

# otherwise we can do it ourselves
cat << EOF >> ${APPDIR}/Setup.sh

export PYTHONPATH=${PACKAGEPATH}:${APPDIR}:\$PYTHONPATH

EOF

echo "Installation complete"
exit 0
