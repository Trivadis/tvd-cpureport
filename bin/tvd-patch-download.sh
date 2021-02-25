#!/bin/bash
# ---------------------------------------------------------------------------
# Trivadis AG, Infrastructure Managed Services
# Saegereistrasse 29, 8152 Glattbrugg, Switzerland
# ---------------------------------------------------------------------------
# Name.......: tvd-patch-download.sh 
# Author.....: Miguel Anjo (ami) miguel.anjo@trivadis.com
# Editor.....: Miguel Anjo
# Date.......: 2021.02.02
# Revision...: 
# Purpose....: Script to dowload patch from MOS 
# Notes......: - The script downloads by default latest RU patch
# Reference..: --
# License....: Licensed under the Universal Permissive License v 1.0 as 
#              shown at http://oss.oracle.com/licenses/upl.
# ---------------------------------------------------------------------------
# Modified...:
# see git revision history for more information on changes/updates
# ---------------------------------------------------------------------------
# Define a bunch of bash option see 
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
#set -o nounset          # stop script after 1st cmd failed
set -o errexit          # exit when 1st unset variable found
set -o pipefail         # pipefail exit after 1st piped commands failed


# - Patches to download -------------------------------------------------
LATEST_CYCLE="JAN2021"
OPATCH_VERSION="JAN2021"  # Downloads always if LATEST_CYCLE=OPATCH_VERSION
# Include Patch list
. $(dirname "$0")/PATCH_JAN2021.lst

# - EOF - Patches to download ---------------------------------------------

# - Customization -------------------------------------------------------
export LOG_BASE=${LOG_BASE-"/tmp"}
# - End of Customization ------------------------------------------------

# - Environment Variables ---------------------------------------------------
# define default values 
VERSION=v0.1.0
DOAPPEND="TRUE"                                                 # enable log file append
VERBOSE="FALSE"                                                 # enable verbose mode
DEBUG="FALSE" 

SCRIPT_NAME=$(basename ${BASH_SOURCE[0]})
SCRIPT_EXEC_DIR=$(dirname ${BASH_SOURCE[0]})
SCRIPT_BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRIPT_BASE=$(dirname ${SCRIPT_BIN})
SCRIPT_DOC="${SCRIPT_BASE}/doc"
SCRIPT_LOG="${SCRIPT_BASE}/log"
TIMESTAMP=$(date "+%Y.%m.%d_%H%M%S")
START_HEADER="INFO: Start of ${SCRIPT_NAME} (Version ${VERSION}) on $(date)"
CURRENT_PWD=$(pwd)

# Path to wget command
WGET=$(which wget)

# Location of cookie file
COOKIE_FILE=/tmp/$$.cookies

# Oracle patch download URL
URL="https://updates.oracle.com/Orion/Download/download_patch"

# - EOF Environment Variables -----------------------------------------------

# - Process input variables -------------------------------------------------
# SSO username and password
SSO_USERNAME=cpureport@trivadis.com
SSO_PASSWORD=tr1vad1$

# - EOF Process input variables ---------------------------------------------

# - Functions ---------------------------------------------------------------
# -----------------------------------------------------------------------
# Purpose....: shows script help
# -----------------------------------------------------------------------
# TODO: add better logging
function show_help () {
  echo 
  echo "$START_HEADER"
  echo 
  echo "./${SCRIPT_NAME} [ -h|--help] [-u|--user USER [-t|--type TYPE] [-r|--release RELEASE] [-p|--platform PLATFORM] [-g||-gi] [-o|--opatch YES|NO] [-l|--location LOCATION] [-v|--verbose]]"
  echo 
  echo "    -h --help      shows this help screen"
  echo "    -v --verbose   adds more verbosity"
  echo "    -u --user      MOS login email (mandatory)"
  echo "    -p --pass      MOS login password (if not given, will ask)"
  echo "    -t --type      patch type: RU, RUR1 or RUR2 (default RU)"
  echo "    -c --cycle     patch cycle, format MMMYY, example JAN21 (default latest cycle)"
  echo "    -r --release   patch version: 122, 18, 19 (default checks installed software)"
  echo "    -e --platform  patch platform: 'linux-x86', 'solaris-x86', 'solaris-sparc', 'aix', 'hp-ux', 'linux-z' (default current platform)"
  echo "    -g --combo        downloads GI+DB Combo (default checks installed software)"
  echo "    -o --opatch    downloads OPatch (default checks installed opatch version, download if newer)"
  echo "    -l --location  downloads location (default current path)"
  echo 
}

# -----------------------------------------------------------------------
# Purpose....: check if a command exists.
# -----------------------------------------------------------------------
function command_exists () {
    command -v $1 >/dev/null 2>&1;
}

# -----------------------------------------------------------------------
# Purpose....: Clean up before exit
# -----------------------------------------------------------------------
function DoMsg () {
    if [[ $VERBOSE == "TRUE" ]]; then
      echo $1
    else 
      if [[ $1 != "DEBUG"* ]]; then
        echo $1
      fi
    fi
}

function CleanAndQuit() {
    # remove temporary files
    DoMsg "DEBUG: Remove temporary files"
    rm "$COOKIE_FILE"
    rm download
    

    # enable verbose to make sure error is echo to STDOUT
    if [[ ${1} -gt 0 ]]; then
        VERBOSE="TRUE"
    fi

    # Parse error code passed to function
    case ${1} in
        0)  DoMsg "END  : of ${SCRIPT_NAME}";;
        1)  DoMsg "ERROR: Exit Code ${1}. Wrong amount of arguments. See usage for correct one.";  show_help ;;
        2)  DoMsg "ERROR: Exit Code ${1}. Wrong arguments (${2}). See usage for correct one.";  show_help ;;
        3)  DoMsg "ERROR: Exit Code ${1}. Missing mandatory argument ${2}. See usage for correct one." show_help ;;
        4)  DoMsg "ERROR: Exit Code ${1}. ${2} requires a mandatory argument.";;
        5)  DoMsg "ERROR: Exit Code ${1}. Login problem to MOS. Possibly invalid username/password.";;
        11) DoMsg "ERROR: Exit Code ${1}. Could not touch file ${2}";;
        12) DoMsg "ERROR: Exit Code ${1}. Could access file ${2}";;
        41) DoMsg "ERROR: Exit Code ${1}. Error creating directory ${2}.";;
        42) DoMsg "ERROR: Exit Code ${1}. Error write to directory ${2}.";;
        90) DoMsg "ERROR: Exit Code ${1}. Function/Method ${2} not yet implemented";;
        99) DoMsg "INFO : Just wanna say hallo.";;
        ?)  DoMsg "ERROR: Exit Code ${1}. Unknown Error.";;
    esac
    exit ${1}
}

function get_platform () {
    DoMsg "DEBUG: uname is $(uname -s)_$(uname -m)"
    case "$(uname -s)_$(uname -m)" in
      "Linux_x86_64")
        PLATFORM="Linux-x86-64";; 
      "SunOS_i86pc")
        PLATFORM="Solaris86-64";;
      "SunOS_sun4u")
        # TODO: Check correct name
        PLATFORM="SOLARIS64";;
      *"AIX"*)
        PLATFORM="AIX64-5L";;
      *)
        PLATFORM="Linux-x86-64"
        echo "ERROR: Platform '$(uname)' not supported. Using '${PLATFORM}'.";;
    esac
    DoMsg "DEBUG: PLATFORM=${PLATFORM}"
}


function get_gi_version () {
  if [[ ! -r /etc/oratab ]]; then
    DoMsg "ERROR: cannot read /etc/oratab."
    CleanAndQuit 3 "-g|--combo"
  fi

  # If line starts with +ASM on /etc/oratab, assumes GI is installed and checks version with oraversion
  if ! grep -q -e "^+ASM" /etc/oratab; then
    COMBO="FALSE"
    DoMsg " INFO: GI is not installed."
  else
    COMBO="TRUE"
    GI_VERSION=$($(grep -v '^#' /etc/oratab | grep ASM | head -1 | cut -d: -f2 )/bin/oraversion -baseVersion | tr -d .)
    DoMsg "DEBUG: GI release $GI_VERSION is installed"
  fi
}


function get_db_versions () {
  if [[ ! -r /etc/oratab ]]; then
    DoMsg "ERROR: cannot read /etc/oratab."
    CleanAndQuit 3 "-r|--release"
  fi
  DB_HOME_LIST=$(grep -v '^#' /etc/oratab | grep . | cut -d: -f2 | sort | uniq || "")
  DoMsg "DEBUG: DB_HOME_LIST is: $DB_HOME_LIST"
  DB_VERSION=()
  for DB_HOME in $DB_HOME_LIST; do
    if [ -x ${DB_HOME}/bin/oraversion ]; then
      VERSION=$(${DB_HOME}/bin/oraversion -baseVersion | tr -d .)
    else # <=12.2
      VERSION=$(${DB_HOME}/bin/sqlplus -v | grep Release | tr -dc '0-9')
    fi
    DoMsg "INFO: Found $DB_HOME release ${VERSION}"
    DB_VERSION+=(${VERSION})
    # echo "DB release ${DB_VERSION[@]: -1} found"
  done;
  DoMsg "DEBUG: DB_VERSION array=${DB_VERSION[*]} "
  DB_VERSION_UNIQUE=$(tr ' ' '\n' <<< "${DB_VERSION[@]}" | sort -u | tr '\n' ' ' | xargs)
  DoMsg "DEBUG: DB_VERSION_UNIQUE=${DB_VERSION_UNIQUE[*]} "
}
# - EOF Functions -----------------------------------------------------------


if [[ $@ < 1 ]]; then
  echo "ERROR: Need at least one argument."
  CleanAndQuit 1  
fi

# - Process input variables -------------------------------------------------
# Initialize all the option variables, as http://mywiki.wooledge.org/BashFAQ/035
SSO_USERNAME=""
SSO_PASSWORD=""
TYPE="RU"
CYCLE=${LATEST_CYCLE}
RELEASE="oratab"
PLATFORM="current"
COMBO=""
OPATCH="updated"
LOCATION="."
VERBOSE="FALSE"

while :; do
    case $1 in
        -h|-\?|--help)
            show_help    # Display a usage synopsis.
            exit
            ;;
        -u|--user)       # MOS Username, mandatory
            if [ "$2" ]; then
                SSO_USERNAME=$2
                shift
            else
                CleanAndQuit 4 "-u|--user"
            fi
            ;;
        -p|--pass)       # MOS Password, if not given, asks
            if [[ "$2" ]]; then
                SSO_PASSWORD=$2
                shift
            else
                CleanAndQuit 4 "-p|--password"
            fi
            ;;
        -t|--type)       # Must be RU, RUR1 or RUR2 (default RU)
            if [[ "$2" ]]; then
              if [[ "$2" != @(RU|RUR1|RUR2) ]]; then 
                CleanAndQuit 2 "--type"
              else
                TYPE=$2
                shift
              fi              
            else
                CleanAndQuit 4 "-t|--type"
            fi
            ;;
        -c|--cycle)       # Must be [JAN|APR|JUL|OCT][XX]|latest
            if [ "$2" ]; then
              if [[ "$2" =~ (JAN|APR|JUL|OCT)(2\d) ]]; then
                CYCLE=$2
                shift
              else 
                CleanAndQuit 2 "--cycle"
              fi
            else
                CleanAndQuit 4 "-c|--cycle"
            fi
            ;;
        -r|--release)       # Must be 122, 18, 19 or 21 (default checks oratab)
            if [ "$2" ]; then
              if [[ "$2" != @(122|18|19|21) ]]; then
                CleanAndQuit 2 "-r|--release"
              else
                RELEASE=$2
                shift
              fi
            else
                CleanAndQuit 4 "-r|--release"
            fi
            ;;
        -e|--platform)   # Must be Linux, AIX, Solaris (default check current OS)
            if [ "$2" ]; then
              if [[ "$2" != @(linux-x86|solaris-x86|solaris-sparc|aix|hp-ux|linux-z) ]]; then
                CleanAndQuit 2 "-e|--platform"
              else
                PLATFORM=$2
                shift
              fi
            else
                CleanAndQuit 4 "-e|--environment"
            fi
            ;;
        -g|--combo)       # Downloads GI combo (default checks if GI installed)
            COMBO="TRUE"
            ;;
        -o|--opatch)       # Downloads also OPatch (default, checks if new exists)
            OPATCH="TRUE"
            ;;
        -l|--location)       # Download location (default current folden)
            if [ "$2" ]; then
                LOCATION=$2
                shift
            else
                CleanAndQuit 4 "-l|--location"
            fi
            ;;

        -v|--verbose)
            VERBOSE="TRUE"
            DoMsg "DEBUG: Verbose mode active"
            ;;
        --)              # End of all options.
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)               # Default case: No more options, so break out of the loop.
            break
    esac
    shift
done
# - EOF Process input variables ---------------------------------------------

DoMsg "${START_HEADER}"

if [[ -z "${SSO_USERNAME}" ]]; then
  CleanAndQuit 3 "-u|--username"
fi

while [[ -z "${SSO_PASSWORD}" ]]; do
  DoMsg "${SSO_USERNAME} Password:"
  read -s SSO_PASSWORD
done

if [[ ${PLATFORM} == "current" ]]; then
  get_platform
fi

if [[ ${RELEASE} == "oratab" ]]; then 
  get_db_versions
else
  case ${RELEASE} in
    122) DB_VERSION_UNIQUE=(122010) ;;
     18) DB_VERSION_UNIQUE=(180000) ;;
     19) DB_VERSION_UNIQUE=(190000) ;;
     21) DB_VERSION_UNIQUE=(210000) ;;
      *) DoMsg "ERROR: Unknown Release"
  esac
fi

if [[ -z "$COMBO" ]]; then
  get_gi_version
else  # Combo IS explicitly requested
  if [[ ${RELEASE} == "oratab" ]]; then
    get_gi_version
  else  # Release IS explicitly requested
    case ${RELEASE} in
      122) GI_VERSION=(122010) ;;
       18) GI_VERSION=(180000) ;;
       19) GI_VERSION=(190000) ;;
       21) GI_VERSION=(210000) ;;
        *) DoMsg "ERROR: Unknown Release"
    esac
  fi
fi

if [[ ! -w "$LOCATION" ]]; then
  DoMsg "ERROR: No write access on $LOCATION " # Cannot use CleanAndQuit: it tries access $LOCATION
  exit 4
fi

if [ ! -d ${SCRIPT_LOG} ]; then 
    echo "INFO: fall back to default log directory \$LOG_BASE=${LOG_BASE}"
    SCRIPT_LOG=${LOG_BASE:-"/var/log"}
fi
readonly LOGFILE="${SCRIPT_LOG}/$(basename ${SCRIPT_NAME} .sh)_${TIMESTAMP}.log"
touch ${LOGFILE} 2>/dev/null
exec 1> >(tee -a "$LOGFILE")    # Open standard out at `$LOG_FILE` for write.
exec 2>&1                       # Redirect standard error to standard out 

DoMsg "DEBUG: SCRIPT_LOG   => $SCRIPT_LOG"
DoMsg "DEBUG: SSO_USERNAME => $SSO_USERNAME"
DoMsg "DEBUG: TYPE         => $TYPE"
DoMsg "DEBUG: CYCLE        => $CYCLE"
DoMsg "DEBUG: RELEASE      => $RELEASE"
DoMsg "DEBUG: PLATFORM     => $PLATFORM"
DoMsg "DEBUG: COMBO/GI     => $COMBO"
DoMsg "DEBUG: OPATCH       => $OPATCH"
DoMsg "DEBUG: LOCATION     => $LOCATION"


# Contact updates site so that we can get SSO Params for logging in
SSO_RESPONSE=$($WGET --user-agent="Mozilla/5.0" https://updates.oracle.com/Orion/Services/download 2>&1 | grep Location)

# Extract request parameters for SSO
SSO_TOKEN=$(echo $SSO_RESPONSE| cut -d '=' -f 2|cut -d ' ' -f 1)
SSO_SERVER=$(echo $SSO_RESPONSE| cut -d ' ' -f 2|cut -d 'p' -f 1,2)
SSO_AUTH_URL=sso/auth
AUTH_DATA="ssousername=$SSO_USERNAME&password=$SSO_PASSWORD&site2pstoretoken=$SSO_TOKEN"

# The following command to authenticate uses HTTPS. This will work only if the wget in the environment
# where this script will be executed was compiled with OpenSSL. Remove the --secure-protocol option
# if wget was not compiled with OpenSSL
# Depending on the preference, the other options are --secure-protocol= auto|SSLv2|SSLv3|TLSv1
$WGET --user-agent="Mozilla/5.0" --secure-protocol=auto --post-data $AUTH_DATA --save-cookies=$COOKIE_FILE --keep-session-cookies $SSO_SERVER$SSO_AUTH_URL --delete-after >> $LOGFILE 2>&1

# Check if login was successful
if ! grep -q ORASSO_AUTH_HINT $COOKIE_FILE; then
  CleanAndQuit 5
else
  DoMsg "INFO: Login to MOS successful"
fi

# Starts download
if [[ $OPATCH == "TRUE" || $LATEST_CYCLE == $OPATCH_VERSION ]]; then
  DoMsg "INFO: Downloading OPatch..."
  # $WGET ...
fi

for VERSION in "${DB_VERSION_UNIQUE[@]}"; do
  if [[ "$COMBO" = "TRUE" && $GI_VERSION == $VERSION ]]; then
    PATCH=$"PATCH_COMBO_${CYCLE}_${VERSION}"
  else
    PATCH=$"PATCH_DB_${CYCLE}_${VERSION}_RU"
  fi    
  DoMsg "INFO: Downloading RU ${CYCLE} for Oracle version ${VERSION} on ${PLATFORM}..."
  DoMsg "DEBUG: Downloading ${PATCH} = ${!PATCH}"
  $WGET --user-agent="Mozilla/5.0" --load-cookies=$COOKIE_FILE --save-cookies=$COOKIE_FILE --keep-session-cookies "${URL}/p${!PATCH}_${VERSION}_${PLATFORM}.zip" -O "${LOCATION}/p${!PATCH}_${VERSION}_${PLATFORM}.zip" >> $LOGFILE 2>&1
done

echo "All downloaded files are:"
ls -l ${LOCATION}/p*.zip

# Cleanup
CleanAndQuit

# --- EOF --------------------------------------------------------------------