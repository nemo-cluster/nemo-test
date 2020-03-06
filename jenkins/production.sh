#!/bin/bash

# shellcheck disable=SC2145
# name of the script withouth the path
scriptname=$(basename "$0")
# path to the folder containing the script
scriptdir=$(dirname "$0")

usage() {
    echo -e "\n Usage: $0 [OPTIONS] -l <list> -p <prefix>
    -h,--help         Help message
    -l,--list         Absolute path to production file   (mandatory: EasyBuild production list)
    -p,--prefix       Absolute path to EasyBuild prefix  (mandatory: installation folder)
    --soft-prefix     Absolute path to EasyBuild software prefix
    --modules-prefix   Absolute path to EasyBuild module prefix
    -r, --robot       Robot path that is going to be used
    -u,--use          Module use colon separated PATH  (optional: Used To testing)
    -e, --eb-path     Easybuild instalation module path (mandatory)
    --hide-deps       Force hide modules listed in 'hide-deps' (TestingEB only)
    --exit-on-error   Exit when an error occurs (TestingEB only)
    --deploy          Deploy nemobuild to the folder and exit (Deploy only)
    "
    exit 1;
}

create_config() {
    if [ ! -e $1 ]; then
        mkdir -p $(dirname $1) 2> /dev/null
        echo "[override]" > $1
    fi
}

longopts="help,list:,prefix:,robot:,use:,eb-path:,hide-deps,exit-on-error,soft-prefix:,modules-prefix:,deploy:"
shortopts="h,l:,p:,r:,u:,e:"
eval set -- $(getopt -o ${shortopts} -l ${longopts} -n ${scriptname} -- "$@" 2> /dev/null)

eb_files=()
eb_lists=()
while [ $# -ne 0 ]; do
    case $1 in
        -f | --force)
            shift
            force_list="$1"
            ;;
        -h | --help)
            usage
            ;;
        -l | --list)
            shift
            mapfile -O ${#eb_files[@]} -t eb_files < $1
            eb_lists+=($1)
            ;;
        -p | --prefix)
            shift
            PREFIX="$1"
            ;;
        --soft-prefix)
            shift
            SOFT_PREFIX="$1"
            ;;
        --modules-prefix)
            shift
            MODULES_PREFIX="$1"
            ;;
        -r | --robot)
            shift
            ROBOT="$1"
            ;;
        -u | --use)
            shift
            use_path="$1"
            ;;
        -e | --eb-path)
            shift
            EB_PATH="$1"
            ;;
        --exit-on-error)
            exit_on_error=true
            ;;
        --hide-deps)
            hidden_deps=true
            ;;
        --deploy)
            shift
            DEPLOY=$1
            ;;
        --)
            ;;
        *)
            usage
            ;;
    esac
    shift
done

# optional EasyBuild arguments
eb_args=()

# --- COMMON SETUP ---
CONFIGFILE="easybuild.cfg"
[ -e $CONFIGFILE ] && rm $CONFIGFILE
create_config $CONFIGFILE
eb_args+=("--configfiles=$CONFIGFILE")

# check prefix folder
if [ -z "$PREFIX" ]; then
    echo -e "\n Prefix folder not defined. Please use the option -p,--prefix to define the prefix folder \n"
    usage
else
  # eb_args+=("--prefix=$PREFIX")
  echo "prefix=$PREFIX" >> $CONFIGFILE
fi

if [ -n "$ROBOT" ]; then
  echo "robot-paths=$ROBOT:%(DEFAULT_ROBOT_PATHS)s" >> $CONFIGFILE
fi


if [ -n "$SOFT_PREFIX" ] ; then
  echo "installpath-software=$SOFT_PREFIX" >> $CONFIGFILE
fi

if [ -n "$MODULES_PREFIX" ]; then
  echo "installpath-modules=$MODULES_PREFIX" >> $CONFIGFILE
fi

if [ -z "$EB_PATH" ]; then
  echo -e "\n Need to specify EasyBuild path. Please use uoption -e, --eb-path \n"
  usage
fi

echo "include-module-naming-schemes=$(pwd)/easybuild-tools/module_naming_scheme/lowercase_categorized_mns.py" >> $CONFIGFILE
echo "module-naming-scheme=LowercaseCategorizedModuleNamingScheme" >> $CONFIGFILE

# --- BUILD ---
module use "$EB_PATH"
module load EasyBuild

if [ -n "$hidden_deps" ]; then
  # get all configs names from all robots path
  robots_paths=$(eb --show-config "${eb_args[@]}" | grep robot-paths | awk -F'=' '{print $2}' | head -1 | tr -d ',')
  possible_deps=$(find  $robots_paths -type f -iname '*.eb' -printf '%h\n' | awk -F/ '{print $NF}' | sort | uniq | tr '\n' ',')
  possible_deps=${possible_deps::-1}
  deps_number=$(echo "${possible_deps}" | tr ',' ' ' | wc -w)
  echo "Found $deps_number possible dependencies to hide"
  echo "hide-deps=$possible_deps" >> $CONFIGFILE
  echo "hide-toolchains=$possible_deps" >> $CONFIGFILE
fi

if [ -n "$DEPLOY" ]; then
  create_config $DEPLOY/config.cfg-tmp
  echo "include-module-naming-schemes=$DEPLOY/module_naming_scheme/lowercase_categorized_mns.py" >> $DEPLOY/config.cfg-tmp
  echo "module-naming-scheme=LowercaseCategorizedModuleNamingScheme" >> $DEPLOY/config.cfg-tmp 
  echo "hide-deps=$possible_deps" >> $DEPLOY/config.cfg-tmp 
  echo "hide-toolchains=$possible_deps" >> $DEPLOY/config.cfg-tmp 
  mv $DEPLOY/config.cfg-tmp $DEPLOY/config.cfg
  rsync -aHhv "$(pwd)/easybuild/" $DEPLOY
  rsync -aHhv "$(pwd)/NemoBuild" "$MODULES_PREFIX/all"
  rsync -aHhv "$(pwd)/easybuild-tools/" $DEPLOY
  
  exit 0
fi

if [ -n "$use_path" ]; then
 echo -e " Aditional path: $use_path "
 module use "$use_path"
 echo -e " Updated MODULEPATH: $MODULEPATH "
fi

# print EasyBuild configuration, module list, production file(s), list of builds
echo -e "\n EasyBuild version and configuration ('eb --version' and 'eb --show-config'(removing hidding commands)): "
echo -e " $(eb --version) \n $(eb --show-config ${eb_args[@]} | grep -vwe ^hide-deps -vwe ^hide-toolchains) \n"
echo -e "Hiding $(eb --show-config ${eb_args[@]} | grep -we ^hide-deps | cut -d= -f2 | wc -w) dependencies\n"
echo -e "Hiding $(eb --show-config ${eb_args[@]} | grep -we ^hide-toolchains | cut -d= -f2 | wc -w) toolchains\n"
echo -e " Modules loaded ('module list'): "
echo -e " $(module list)"
echo -e " Compilation file: " "${eb_lists[@]}" "\n"
echo -e " List of builds (including options):"
for ((i=0; i<${#eb_files[@]}; i++)); do
# use eval to expand environment variables in the EasyBuild options of each build
    eb_files[i]=$(eval "${eb_files[i]}" 2> /dev/null || echo "${eb_files[i]}")
    echo "${eb_files[$i]}"
done

# checks dependency list using dry run
echo -e eb "${eb_files[@]}" -Dr "${eb_args[@]}"
dryrun=$(eb "${eb_files[@]}" -Dr "${eb_args[@]}" 2>&1)
if [[ "$dryrun" =~ "ERROR" ]]; then
 echo -e "$dryrun" | grep "ERROR"
 exit 1
fi


# start time
echo -e "\n Starting builds on $(date)"
starttime=$(date +%s)
# compile software with prefix, with
status=0
for((i=0; i<${#eb_files[@]}; i++)); do
  echo -e "\n===============================================================\n"
  # define name and version of the current build starting from the recipe name (obtained removing EasyBuild options from eb_files)
  recipe=$(echo "${eb_files[$i]}" | cut -d' ' -f 1)
  name=$(echo "$recipe" | cut -d'-' -f 1)
  echo -e eb "${eb_files[$i]}" -r "${eb_args[@]}"
  eb "${eb_files[$i]}" -r "${eb_args[@]}"
  status=$((status+$?))
done

# end time
endtime=$(date +%s)
# time difference
difftime=$((endtime-starttime))
# convert seconds to hours minutes seconds format
 h=$((difftime/3600))
 m=$(( (difftime%3600) /60))
 s=$((difftime%60))
echo -e "\n Builds ended on $(date) (elapsed time is $difftime s : ${h}h ${m}m ${s}s) \n"

# cumulative exit status of all the builds and the last command
exit $((status+$?))
