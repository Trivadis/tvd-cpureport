#!/bin/bash
# ---------------------------------------------------------------------------
# Trivadis AG, Infrastructure Managed Services
# Saegereistrasse 29, 8152 Glattbrugg, Switzerland
# ---------------------------------------------------------------------------
# Name.......: OPatch_upgrade.sh
# Author.....: Miguel Anjo (ami) miguel.anjo@trivadis.com
# Editor.....: Miguel Anjo
# Date.......: 2019.05.05
# Revision...: 
# Purpose....: Script to upgrade installed versions of OPatch
# Notes......: - The script uses BasEnv to get the list of Oracle Homes
#              - Run as: oracle
# Reference..: --
# License....: Licensed under the Universal Permissive License v 1.0 as 
#              shown at http://oss.oracle.com/licenses/upl.
# ---------------------------------------------------------------------------
# Modified...:
# see git revision history for more information on changes/updates
# ---------------------------------------------------------------------------


# OPatches patchfile location
patches_location="/db_share/share/software/oracle/opatch/"

# Current versions of OPatch. Can be part of the variables file
# The latest OPatch should be named:
#    For Oracle 112: p6880880_112000_Linux-x86-64.zip
#    For Oracle 122: p6880880_122010_Linux-x86-64.zip
#    For Oracle 19c: p6880880_190000_Linux-x86-64.zip
##########################################################################

# Path of the script as it was called
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Get output print
source ${DIR}/etc_log_functions.sh

# Is this only to chekc the versions?
if [[ "$1" == "check" ]]; then
  CHECK=1
fi

# Check if script was called by root when is not only check
if [[ -z $CHECK && $EUID != 0 ]]; then
    ecrit "Please run this script as root"
    exit
fi

# Get list of ORACLE_HOMES. Needs to have Trivadis BasEnv installed
oh=$(getent passwd oracle | cut -d: -f6)
BE_HOME=$(cat ${oh}/.BE_HOME | cut -d'=' -f2)
if [ ! -z $BE_HOME ]; then
  HOMES=$( cat ${BE_HOME}/etc/orahometab | grep -E ';grinf|;rdbms|;client' | cut -d ';' -f1 )
else
  ecrit "Could not get list of ORACLE_HOMES. Exiting."
  exit 3
fi

# Function to get current version of OPatch
function check_opatch_version {
if [ -f ${1}/OPatch/opatch ]; then
    opatch_version=$(${1}/OPatch/opatch version | grep Version | cut -d ':' -f 2 | tr -d '[:space:]')
    edebug  "$opatch_version"
  else
    eerror "OPatch not found. Exit."
        exit 1
  fi
}

# Function to check if it is latest version
#   If not the latest, it updates OPatch
#   Backup is kept as $ORACLE_HOME/OPatch_old
function update_opatch {
   local home=${1}
   local home_version=${2}
   rm -rf ${home}/OPatch_old
   mv ${home}/OPatch ${home}/OPatch_old
   mkdir ${home}/OPatch
   chown oracle:dba ${home}/OPatch
   su -c "unzip -oq ${patches_location}/p6880880_${home_version}_Linux-x86-64.zip -d ${home}" oracle
   check_opatch_version ${home}
   eok "${home} has now OPatch version $opatch_version"
}

#
# Main part of the script
#
for home in $HOMES; do
  einfo "Found home $home"
  if [ -f ${home}/OPatch/opatch ]; then
    check_opatch_version ${home}
    einfo "Current OPatch version: $opatch_version"
  else
    ecrit "E:   OPatch not found. Exit."
    exit 1
  fi

  # There is Opatch, check if needs update
  if [[ $home =~ 11\.2 ]]; then
    home_version=112000
    opatch_current=$( unzip -p ${patches_location}/p6880880_${home_version}_Linux-x86-64.zip OPatch/version.txt | cut -d':' -f2 )
  elif [[ $home =~ 12\.2 ]]; then
    home_version=122010
    opatch_current=$( unzip -p ${patches_location}/p6880880_${home_version}_Linux-x86-64.zip OPatch/version.txt | cut -d':' -f2 )
  elif [[ $home =~ 19 ]]; then
    home_version=190000
    opatch_current=$( unzip -p ${patches_location}/p6880880_${home_version}_Linux-x86-64.zip OPatch/version.txt | cut -d':' -f2 )
  else
    ecrit "Unknown ORACLE_HOME version. Exit."
    exit 2
  fi


  if [ $opatch_version != $opatch_current ]; then
    # It's an old version, if only check, does nothing, else updates
    ewarn "${home} OPatch version $opatch_version is older than current OPatch version ${opatch_current}."
    if [ -n "$CHECK" ]; then
      enotify "  Please run as root $0 "
      exit 1
    else
      enotify "  updating OPatch..."
      update_opatch $home $home_version
    fi
  else
    eok "${home} has already the latest OPatch version. "
  fi
done;
