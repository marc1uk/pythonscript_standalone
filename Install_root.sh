#!/bin/bash
#set -x
#set -e   # we can't set this as some commands may be expected to fail

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

# first argument if given is installation destination:
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
	DEPS=(git make gcc-c++ gcc binutils libX11-devel libXpm-devel libXft-devel libXext-devel python openssl-devel fftw-devel libuuid-devel)
	# centos7 requires cmake3 from epel
	RHVER=$(grep "VERSION_ID" /etc/os-release | cut -d\" -f2)
	RHOLD=$(echo -e "8\n${RHVER}" | sort -V -C; echo $?)
	if [ ${RHOLD} -eq 1 ]; then
		# we need to use 'epel-release' to acquire cmake3.
		DEPS+=("cmake3")
		DEPS+=("epel-release")
	else
		DEPS+=("cmake")
	fi
	for DEP in "${DEPS[@]}"; do
		echo "looking for ${DEP}..."
		# FIXME this is not a perfect check as 'grep' will match anything with a matching element
		# in its name, e.g. some python3 add-on, even if python3 itself isn't installed.
		# moreover, it will NOT find installations like 'rh-python38-python-libs.x86_64'
		# as would be the case if python-3.8 is installed via epel or somesuch
		GOTDEP=$(yum list installed 2>/dev/null | grep "${DEP}" >/dev/null 2>&1; echo $?)
		if [ ${GOTDEP} -ne 0 ]; then
			echo "not found"
			NEEDDEPS="${NEEDDEPS} ${DEP}"
		fi
	done
elif [ ${DEBIANLIKE} -eq 0 ]; then
	echo "debian based OS"
	DEPS=(dpkg-dev cmake g++ gcc binutils libx11-dev libxpm-dev libxft-dev libxext-dev python libssl-dev libfftw3-dev)
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
	echo "gcc-c++ (g++5 or newer) gcc make cmake git python3 python3-libs python3-devel python3-pip which"
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

# if we have a pre-existing g++ install, check the version is >5 (required to build ROOT >6.26)
# well ok, we can support up to ROOT 6.24 with gcc4.8
ROOTVER="6.28.04"
if [ $(which g++ &> /dev/null; echo $?) -eq 0 ]; then
	GCCVER=$(g++ -dumpversion)
	GCCOK=$(echo -e "5.0\n${GCCVER}" | sort -V -C; echo $?)
	if [ ${GCCOK} -ne 0 ]; then
		# installing multiple g++ versions is usually tricky, so let's leave that to the user.
		echo "Your g++ version is not sufficient to build ROOT 6.26!"
		# see if we can fall back to 6.24...
		GCCOK=$(echo -e "4.8\n${GCCVER}" | sort -V -C; echo $?)
		if [ ${GCCOK} -ne 0 ]; then
			echo "please install g++ 5.0 or newer and retry"
			exit 1
		else
			echo "falling back to ROOT v6.24..."
			ROOTVER="6.24.08"
		fi
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
						# if we need to install epel packages, we must install epel separately first
						if [[ " ${NEEDDEPS[*]} " =~ " epel-release " ]]; then
							yum install -y "epel-release"
						fi
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


cd ${INSTALLDIR}
# there is an existing release for centos8, so we don't need to build from source
#wget https://root.cern/download/root_v${ROOTVER}.Linux-centos8-x86_64-gcc8.5.tar.gz
#if [ $? -ne 0 ]; then
#	echo "Error downloading ROOT: check network connection"
#	exit 1
#fi
#tar -xzvf root_v${ROOTVER}.Linux-centos8-x86_64-gcc8.5.tar.gz
#rm -f root_v${ROOTVER}.Linux-centos8-x86_64-gcc8.5.tar.gz
#mv root root_v${ROOTVER}
#source ${INSTALLDIR}/root_v${ROOTVER}/bin/thisroot.sh

# to be more general though we should build from source
wget https://root.cern/download/root_v${ROOTVER}.source.tar.gz
if [ $? -ne 0 ]; then
	echo "Error downloading ROOT: check network connection"
	exit 1
fi
tar -xzvf root_v${ROOTVER}.source.tar.gz
rm -f root_v${ROOTVER}.source.tar.gz
mkdir root_v${ROOTVER}   # install dir
mkdir rootbuild          # build dir (temporary)
cd rootbuild
cmake3 ../root-${ROOTVER} -Dgdml=ON -Dxml=ON -Dmt=ON -Dmathmore=ON -Dx11=ON -Dimt=ON -Dtmva=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo -Dpythia6=ON -Dfftw3=ON -DCMAKE_INSTALL_PREFIX=${INSTALLDIR}/root_v${ROOTVER} #-DCMAKE_CXX_STANDARD=14
make -j$(nproc)
make install
cd ../
rm -r  root-${ROOTVER}
rm -r rootbuild
source ${INSTALLDIR}/root_v${ROOTVER}/bin/thisroot.sh

# second argument is the application directory, as we need to update Setup.sh
APPDIR="/web"
if [ $# -gt 1 ]; then
	APPDIR=$2
fi
# check the Setup.sh script is found and is writable
if [ ! -w ${APPDIR}/Setup.sh ]; then
	echo "${APPDIR}/Setup.sh not found or not writable!"
	echo "Please add 'source ${INSTALLDIR}/root_v${ROOTVER}/bin/thisroot.sh' manually"
	exit 0
fi
# if found and writable add ROOT setup
cat << EOF >> ${APPDIR}/Setup.sh

export source ${INSTALLDIR}/root_v${ROOTVER}/bin/thisroot.sh

EOF

echo "checking installation of cppyy"
checkcppyy
if [ $? -ne 0 ]; then
	echo "Installation failed. Please manually install cppyy."
	exit 1
fi

# otherwise install succeeded

echo "Installation complete"
exit 0
