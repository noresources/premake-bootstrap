#!/usr/bin/env bash
###################################################
# Generate embedded lua scripts file 
# like the premake 'embed' action

usage()
{
	cat << EOF
$(basename "${0}") [ -h] [-o <output directory>]
	With
		-o --output
			Set embedded scripts file output directory
			Default: ${defaultOutputDirectory}
		-n --name
			Set embedded scripts file name
			Default: ${defaultPremakeEmbeddedScriptFile}
		-c --cc
			C compiler
			Default: ${cc}
		-l --luac
			${luaPremakeVersion} compiler
			Default: $(luac)
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

# Get real absolute path of a file or directory
ns_realpath()
{
	local inputPath=
	if [ $# -gt 0 ]
	then
		inputPath="${1}"
		shift
	fi
	local cwd="$(pwd)"
	[ -d "${inputPath}" ] && cd "${inputPath}" && inputPath="."
	while [ -h "${inputPath}" ] ; do inputPath="$(readlink "${inputPath}")"; done
	
	if [ -d "${inputPath}" ]
	then
		inputPath="$(cd -P "$(dirname "${inputPath}")" && pwd)"
	else
		inputPath="$(cd -P "$(dirname "${inputPath}")" && pwd)/$(basename "${inputPath}")"
	fi
	
	cd "${cwd}" 1>/dev/null 2>&1
	echo "${inputPath}"
}

# Output files listed in manifests
# Use lua if available, otherwise, parse file manually
manifest_filelist()
{
	local manifestPath="${1}"
	if which lua 1>/dev/null 2>&1
	then
		lua -e 'for _, f in ipairs(dofile("'${manifestPath}'")) do print(f) end'
	else
		# We assume that all manifests respect the same formatting policy
		# * A single "return {}" instruction
		# * One file per line
		# * Use double quotes 
		sed -n 's,[[:space:]]"\(.*\.lua\)".*,\1,p' "${manifestPath}"
	fi
}

short_file_name ()
{
	local file="${1}"
	file="${file#${premakeRootPath}/}"
	echo "${file#modules/}"
}

append_script_bytecode()
{
	local file="${1}"
	local index=${2}
	
	local input="${file}"
	
	local input="$(ns_mktemp)"
	${luac} -o "${input}" "${file}"
			
	echo "// $(short_file_name "${file}")"
	echo -n "static const unsigned char builtin_script_${index}[] = {"
	"${bytecodeBin[@]}" "${input}"
	
	[ -f "${input}" ] && rm -f "${input}"
		
	echo '};'
}

cleanup ()
{
	[ -f "${bytecodeBin}" ] && rm -f "${bytecodeBin}"
	echo -n ''
}

trap cleanup EXIT

scriptFilePath="$(ns_realpath "${0}")"
scriptPath="$(dirname "${scriptFilePath}")"
premakeRootPath="$(ns_realpath "${scriptPath}/..")"
defaultOutputDirectory="${premakeRootPath}/src/host"
outputDirectory="${defaultOutputDirectory}"
maxLineLength=4096
defaultPremakeEmbeddedScriptFile='scripts.c'
premakeEmbeddedScriptFile="${defaultPremakeEmbeddedScriptFile}"
bytecodeBin="$(ns_mktemp)"
luac="$(which luac)"
userDefinedLuac=false

# Default compiler
cc=''
for x in cc gcc clang egrep
do
	which ${x} 1>/dev/null 2>&1 && cc=${x} && break
done

# Get premake lua version
luaPremakeVersion="$(egrep "#define[[:space:]]LUA_VERSION[[:space:]]" "${premakeRootPath}/src/host/lua/src/lua.h" | cut -f 2 -d'"')"

####################
# Parse command line
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
		-n|--name)
			premakeEmbeddedScriptFile="${2}"
			shift
			
			if [ -z "${premakeEmbeddedScriptFile}" ]
			then
				echo 'Invalid output output script name' 1>&2
				usage
				exit 1
			fi
		;;
		-c|--cc)
			cc="${2}"
			shift
			if [ ! -x "${cc}" ] && ! which "${cc}" 1>/dev/null 2>&1
			then
				echo "Invalid compiler '${cc}'" 1>&2
				usage
				exit 1
			fi
			;;
		-l|--luac)
			luac="${2}"
			userDefinedLuac=true
			shift
			
			if [ -x "${luac}" ] && ! which "${luac}" 1>/dev/null 2>&1
			then
				echo "Invalid compiler '${cc}'" 1>&2
				usage
				exit 1
			fi
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
for x in sed perl luac
do
	if ! which ${x} 1>/dev/null 2>&1
	then
		echo "${x} is required to create embedded script file" 1>&2
		exit 1
	fi
done

# Check lua version
luacVersion="$(${luac} -v | head -n 1 | cut -f 1-2 -d' ')"
if [ "${luacVersion#${luaPremakeVersion}}" = "${luacVersion}" ]
then
	luaPremakeVersionNumber="$(echo "${luaPremakeVersion}" | cut -f 2 -d' ')"
	if ${userDefinedLuac}
	then
		echo "User defined luac '${luac}' version (${luacVersion}) is not compatible with premake Lua release (${luaPremakeVersion})" 1>&2
		exit 1
	fi
	
	if ! which "luac${luaPremakeVersionNumber}" 1>/dev/null 2>&1
	then
		echo "Unable to find a lua compiler compatible with premake Lua release (${luaPremakeVersion})" 1>&2
		exit 1
	fi 
	
	luac="$(which "luac${luaPremakeVersionNumber}")"
	echo 'Force luac version' ${luac}
fi

[ -x "${luac}" ] \
&& luac="$(ns_realpath "${luac}")" \
|| luac="$(which "${luac}")"

[ -x "${cc}" ] \
&& cc="$(ns_realpath "${cc}")" \
|| cc="$(which "${cc}")"

echo cc ${cc}
echo luac ${luac}

####################
# Generate bytecode program
premakeEmbeddedScriptFilePath="${outputDirectory}/${premakeEmbeddedScriptFile}"

if ! ${cc} -o "${bytecodeBin}" "${scriptPath}/bytecode.c"
then
	echo 'Failed to compile bytecode program' 1>&2
	exit 1
fi

####################
# Generate scripts.c
premakeEmbeddedScriptFilePath="${outputDirectory}/${premakeEmbeddedScriptFile}"

unset premakeManifestFilePaths
while read f
do
	premakeManifestFilePaths=("${premakeManifestFilePaths[@]}" "${f#${premakeRootPath}/}")
done << EOF
$(find "${premakeRootPath}" -name '_manifest.lua' | sort)
EOF

cat > "${premakeEmbeddedScriptFilePath}" << EOF
/* Premake's Lua scripts, as static data buffers for release mode builds */
/* DO NOT EDIT - this file is autogenerated - see BUILD.txt */
/* To regenerate this file, run: embed.sh -o <folder> */

#include "premake.h"
EOF

unset builtinScriptPaths
for m in "${premakeManifestFilePaths[@]}"
do
	manifestPath="${premakeRootPath}/${m}"
	manifestDirectory="$(dirname "${manifestPath}")"
	manifestBaseDirectory="$(dirname "${manifestDirectory}")"
	
	while read f
	do
		builtinScriptPath="${manifestDirectory}/${f}"
		builtinScriptPaths=("${builtinScriptPaths[@]}" "${builtinScriptPath}")
		builtinScriptPath="${builtinScriptPath#${manifestBaseDirectory}/}"
	done << EOF 
$(manifest_filelist "${manifestPath}")
EOF
done
	
# Manually added files
for f in \
	"src/_premake_main.lua" \
	"src/_manifest.lua" \
	"src/_modules.lua"
do
	builtinScriptPath="${premakeRootPath}/${f}"
	builtinScriptPaths=("${builtinScriptPaths[@]}" "${builtinScriptPath}")
done

fileIndex=0
for f in "${builtinScriptPaths[@]}"
do
	append_script_bytecode "${f}" ${fileIndex} >> "${premakeEmbeddedScriptFilePath}"
	fileIndex=$(expr ${fileIndex} + 1)
done

echo 'const buildin_mapping builtin_scripts[] = {' >> "${premakeEmbeddedScriptFilePath}" 

fileIndex=0
for f in "${builtinScriptPaths[@]}"
do
	f="${f#${premakeRootPath}/}"
	echo -e "\t{\"${f}\", builtin_script_${fileIndex}, sizeof(builtin_script_${fileIndex})}," >> "${premakeEmbeddedScriptFilePath}"
	fileIndex=$(expr ${fileIndex} + 1)
done
cat >> "${premakeEmbeddedScriptFilePath}" << EOF
	{NULL, NULL, 0}
};
EOF
