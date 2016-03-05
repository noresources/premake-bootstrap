#!/usr/bin/env bash
###################################################
# Generate a GNU makefile to build premake

usage()
{
	cat << EOF
$(basename "${0}") [ -h] [-e <embedded lua script file>] [-o <output directory>] [-t <target directory>]
	With
		-o --output
			Set Makefile and binary output path
			Default: ${defaultOutputDirectory}
		-e --scripts
			Embedded scripts file location
			If not set, look in default location src/host/scripts.c
			If scripts file does not exists, use embed.sh script to generate it
		-t --target
			Premake binary output directory
			Default: ${defaultTargetDirectory}
		-h --help
			This help
EOF
}

ns_mktemp()
{
	local key=
	if [ $# -gt 0 ]
	then
		key="${1}"
		shift
	else
		key="$(date +%s)"
	fi
	if [ "$(uname -s)" = 'Darwin' ]
	then
		#Use key as a prefix
		mktemp -t "${key}"
	elif which 'mktemp' 1>/dev/null 2>&1 \
		&& mktemp --suffix "${key}" 1>/dev/null 2>&1
	then
		mktemp --suffix "${key}"
	else
		local __ns_mktemp_root=
		for __ns_mktemp_root in "${TMPDIR}" "${TMP}" '/var/tmp' '/tmp'
		do
			[ -d "${__ns_mktemp_root}" ] && break
		done
		[ -d "${__ns_mktemp_root}" ] || return 1
		local __ns_mktemp="/${__ns_mktemp_root}/${key}.$(date +%s)-${RANDOM}"
		touch "${__ns_mktemp}" && echo "${__ns_mktemp}"
	fi
}

ns_relativepath()
{
	local from=
	if [ $# -gt 0 ]
	then
		from="${1}"
		shift
	fi
	local base=
	if [ $# -gt 0 ]
	then
		base="${1}"
		shift
	else
		base="."
	fi
	[ -r "${from}" ] || return 1
	[ -r "${base}" ] || return 2
	[ ! -d "${base}" ] && base="$(dirname "${base}")"  
	[ -d "${base}" ] || return 3
	from="$(ns_realpath "${from}")"
	base="$(ns_realpath "${base}")"
	c=0
	sub="${base}"
	newsub=""
	while [ "${from:0:${#sub}}" != "${sub}" ]
	do
		newsub="$(dirname "${sub}")"
		[ "${newsub}" == "${sub}" ] && return 4
		sub="${newsub}"
		c="$(expr ${c} + 1)"
	done
	res="."
	for ((i=0;${i}<${c};i++))
	do
		res="${res}/.."
	done
	res="${res}${from#${sub}}"
	res="${res#./}"
	echo "${res}"
}

ns_realpath()
{
	local __ns_realpath_in=
	if [ $# -gt 0 ]
	then
		__ns_realpath_in="${1}"
		shift
	fi
	local __ns_realpath_rl=
	local __ns_realpath_cwd="$(pwd)"
	[ -d "${__ns_realpath_in}" ] && cd "${__ns_realpath_in}" && __ns_realpath_in="."
	while [ -h "${__ns_realpath_in}" ]
	do
		__ns_realpath_rl="$(readlink "${__ns_realpath_in}")"
		if [ "${__ns_realpath_rl#/}" = "${__ns_realpath_rl}" ]
		then
			__ns_realpath_in="$(dirname "${__ns_realpath_in}")/${__ns_realpath_rl}"
		else
			__ns_realpath_in="${__ns_realpath_rl}"
		fi
	done
	
	if [ -d "${__ns_realpath_in}" ]
	then
		__ns_realpath_in="$(cd -P "$(dirname "${__ns_realpath_in}")" && pwd)"
	else
		__ns_realpath_in="$(cd -P "$(dirname "${__ns_realpath_in}")" && pwd)/$(basename "${__ns_realpath_in}")"
	fi
	
	cd "${__ns_realpath_cwd}" 1>/dev/null 2>&1
	echo "${__ns_realpath_in}"
}

scriptFilePath="$(ns_realpath "${0}")"
scriptPath="$(dirname "${scriptFilePath}")"
premakeRootPath="$(ns_realpath "${scriptPath}/..")"

kernel="$(uname -s)"

defaultEmbeddedScriptFilePath="${premakeRootPath}/src/host/scripts.c"
embeddedScriptFilePath="${defaultEmbeddedScriptFilePath}"
makefileName="Premake5.make"
defaultOutputDirectory="${premakeRootPath}"
outputDirectory="${defaultOutputDirectory}"
defaultTargetDirectory="${premakeRootPath}/bin/release"
targetDirectory="${defaultTargetDirectory}"

while [ ${#} -gt 0 ]
do
	case "${1}" in
		-o|--output)
			outputDirectory="${2}"
			shift
			
			if ! mkdir -p "${outputDirectory}"
			then 
				echo 'Invalid output directory' 1>&2
				usage
				exit 1
			fi
		;;
		-e|--scripts)
			embeddedScriptFilePath="${2}"
			if ! mkdir -p "$(dirname "${embeddedScriptFilePath}")"
			then 
				echo 'Invalid embedded scripts file directory' 1>&2
				usage
				exit 1
			fi
			shift
			
			embeddedScriptFilePath="$(ns_realpath "$(dirname "${embeddedScriptFilePath}")")/$(basename "${embeddedScriptFilePath}")"
		;;
		-t|--target)
			targetDirectory="${2}"
			shift
			
			if ! mkdir -p "${targetDirectory}"
			then 
				echo 'Invalid target directory' 1>&2
				usage
				exit 1
			fi
			
			targetDirectory="$(ns_realpath "${targetDirectory}")"
		;;
		-h|--help)
			usage
			exit 0
		;;
		-*)
			echo "Invalid option '${1}'" 1>&2
			usage
			exit 1
		;;
		*)
			echo "Invalid argument '${1}'" 1>&2
			usage
			exit 1
		;;
	esac
	
	shift
done

####################
# Check requirements

####################
# Generate makefile

makefilePath="${outputDirectory}/${makefileName}"
premakeSourceFiles=("${embeddedScriptFilePath}")
unset premakeLinkFlags
premakeBuildFlags=(-Wall -Wextra -Os)
premakeDefines=(NDEBUG)

# Exclude files, relative to preamke root
premakeExcludeFiles=(\
	"contrib/lua/src/lauxlib.c" \
	"contrib/lua/src/lua.c" \
	"contrib/lua/src/luac.c" \
	"contrib/lua/src/print.c" \
)

if [ "${embeddedScriptFilePath}" != "${defaultEmbeddedScriptFilePath}" ]
then
	premakeExcludeFiles=("${premakeExcludeFiles[@]}" \
		"${defaultEmbeddedScriptFilePath#${premakeRootPath}/}"\
	)
fi

premakeIncludeDirectories=(\
	"${premakeRootPath}/src/host" \
	"${premakeRootPath}/contrib/lua/src" \
)

if [ "${kernel}" = 'Darwin' ]
then
	premakeDefines=("${premakeDefines[@]}" LUA_USE_MACOSX)
	premakeLinkFlags=("${premakeLinkFlags[@]}" -framework CoreServices)
	premakeBuildFlags=("${premakeBuildFlags[@]}" -mmacosx-version-min=10.4)
elif [ "${kernel}" = 'Linux' ]
then
	premakeDefines=("${premakeDefines[@]}" LUA_USE_POSIX LUA_USE_DLOPEN)
	premakeLinkFlags=("${premakeLinkFlags[@]}" -rdynamic -ldl -lm)
# TODO bsd, hurd etc.
fi

# Create source file list
for d in \
	src \
	contrib/lua
do
	while read f
	do
		r="${f#${premakeRootPath}/}"
		add=true
		
		# Do not add files marked as excluded
		for x in "${premakeExcludeFiles[@]}"
		do
			if [ "${r}" = "${x}" ]
			then
				add=false
				break
			fi
		done
		
		# Do not add files in etc directory of lua sources
		[ "${r}" = "${r#contrib/lua/etc/}" ] || add=false
			
		${add} && premakeSourceFiles=("${premakeSourceFiles[@]}" "${f}")
		
	done << EOF
	$(find "${premakeRootPath}/${d}" \( -name '*.c' \))
EOF
done

# Writing makefile
cat > "${makefilePath}" << EOF
# premake

ifndef CC
	CC = cc
endif

PREMAKE_SRC := $(for f in "${premakeSourceFiles[@]}"; do
	echo -e "\t${f} \\"
done)

EMBEDDED_SCRIPTS_FILE := ${embeddedScriptFilePath}
TARGETDIR := ${targetDirectory}
TARGET := \$(TARGETDIR)/premake5

INCLUDES := $(for d in "${premakeIncludeDirectories[@]}"; do
	echo -e "\t-I'${d}' \\"
done)

DEFINES := $(for d in "${premakeDefines[@]}"; do
	echo -e "\t-D${d} \\"
done)

ALL_CFLAGS := \$(CFLAGS) \$(INCLUDES) \$(DEFINES) $(echo "${premakeBuildFlags[@]}")
ALL_LDFLAGS := \$(LDFLAGS) ${premakeLinkFlags[@]}

.PHONY: all clean

all: \$(EMBEDDED_SCRIPTS_FILE) \$(TARGET)

\$(EMBEDDED_SCRIPTS_FILE): 
	@echo Create embedded script file
	@${scriptPath}/embed.sh -o "$(dirname "${embeddedScriptFilePath}")" -n "$(basename "${embeddedScriptFilePath}")"

\$(TARGETDIR): 
	@echo Create target directory
	@mkdir -p "\$(TARGETDIR)" 

\$(TARGET): \$(TARGETDIR) \$(PREMAKE_SRC)
	@echo Building premake5
	@\$(CC) \$(ALL_CFLAGS) -o "\$(TARGET)" \$(PREMAKE_SRC) \$(ALL_LDFLAGS)
	
clean:  
	@echo Cleaning premake5
	@rm -f "\$(TARGET)"	 
EOF
