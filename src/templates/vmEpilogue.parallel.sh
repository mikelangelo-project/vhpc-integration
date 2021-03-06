#!/bin/bash
#
# Copyright 2015 HLRS, University of Stuttgart
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


#============================================================================#
#                                                                            #
#                          GLOBAL CONFIGURATION                              #
#                                                                            #
#============================================================================#

# source the global profile, for getting DEBUG and TRACE flags if set
source /etc/profile.d/99-mikelangelo-hpc_stack.sh;

#
# Random unique ID used for connecting jobs with generated files
# (when we need to generate scripts there's no jobID, yet)
#
RUID=__RUID__;

#
# Indicates debug mode.
#
DEBUG=__DEBUG__;

#
# Indicates trace mode.
#
TRACE=__TRACE__;

# PBS_JOBID set in environment ?
if [ $# -lt 1 ] \
  && [ -z ${PBS_JOBID-} ] ; then
    echo "PBS_JOBID is not set! usage: $(basename ${BASH_SOURCE[0]}) <jobID>"; # relevant if not executed by Torque, but manually
    exit 1;
elif [ $# -ge 1 ]; then
  #workaround until SendEnv is used for SSH
  export PBS_JOBID=$1;
fi

#
#
#
source $SCRIPT_BASE_DIR/common/config.sh;
source $SCRIPT_BASE_DIR/common/functions.sh;



#============================================================================#
#                                                                            #
#                          SCRIPT CONFIGURATION                              #
#                                                                            #
#============================================================================#


#
# Rank0's user defined persistent disk
#
DISK=__DISK__;

# List of all domain XMLs
declare -a VM_DOMAIN_XML_LIST=$(ls $DOMAIN_XML_PATH_NODE/*.xml | sed 's/ /,/g');


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
#
_releaseVMIPs(){
  logDebugMsg "Releasing local VM's IPs.";
  
  if [ ! -f "$LOCAL_VM_IP_FILE" ]; then
    logWarnMsg "Local PBS_VM_NODEFILE '$LOCAL_VM_IP_FILE' not found!";
  else
    # on each node of a job, collect the running VMs' IPs and write them to the vnode-file
    for vmIP in $(cat $LOCAL_VM_IP_FILE | uniq); do
      logDebugMsg "Releasing VM's IP: '$vmIP'";
      if $PARALLEL; then
        cmd="dhclient -r & exit";
      else
        cmd="dhclient -r";
      fi
      if $PARALLEL; then
        ssh $SSH_OPTS $vmIP $cmd & continue;
      else
        ssh $SSH_OPTS $vmIP $cmd;
      fi
    done
  fi
}


#---------------------------------------------------------
#
# In contrast to the root epilogue* cleanup function this
# one considers local user disks that may contain job output
# and need to be copied back to their original location
#
cleanUpVMs() {
  
  totalCount=${#VM_DOMAIN_XML_LIST[@]};
  
  # give back the IPs
  _releaseVMIPs; ## NOTE: also present in metadata as runlevel service script
  
  # check if there is an error on remote hosts
  checkRemoteNodes;
  
  # let remote processes know that we started our work
  informRemoteProcesses;
  
  #
  logDebugMsg "Shutting down and destroying all local VMs now.";
  vmNo=1;
  for domainXML in ${VM_DOMAIN_XML_LIST[@]}; do
    #
    logDebugMsg "Processing VM number '$vmNo/$totalCount' booted from domainXML='$domainXML'.";
    if $PARALLEL; then
      _destroyVM $vmNo $totalCount $domainXML & continue;
    else
      _destroyVM $vmNo $totalCount $domainXML;
    fi
    # increase counter
    vmNo=$(($vmNo + 1));
  done
  
  logDebugMsg "Destroying ($vmNo) local VM done.";
  return 0;
}


#---------------------------------------------------------
#
# Destroys all job related VMs.
#
_destroyVM() {
  
  if [ $# -ne 3 ]; then
    logErrorMsg "Function '_destroyVM' called with '$#' arguments, '3' are expected.\nProvided params are: '$@'" 2;
  fi
  
  i=$1;
  totalCount=$2;
  domainXML=$3;
  startDate="$(date +%s)";
  
  # grep domain name from VMs domainXML
  domainName="$(grep -E '<name>.*</name>' $domainXML | cut -d'>' -f2 | cut -d'<' -f1)";
  logTraceMsg "VM number '$i/$totalCount' has domainName '$domainName'.";
  
  # construct libVirt log file name for the VM
  vmLogFile=$VMLOG_FILE_PREFIX/$i-libvirt.log; # keep in sync with the name use in the prologue
  
  # create lock file
  logDebugMsg "Waiting for VM domain name '$domainName', using lock dir: '$LOCKFILES_DIR'";
  lockFile="$LOCKFILES_DIR/$domainName";
  touch $lockFile;
  
  # if user disk is present, we need a clean shutdown first
  # FIXME the seed.img and sys iso needs to be skipped !
  if false && [ -n "$(grep '<disk type=' $domainXML | grep file | grep disk)" ]; then
    
    logTraceMsg "There is a disk attached to VM '$i/$totalCount' with domainName '$domainName'.";
    
    # shutdown VM
    logTraceMsg "Shutdown VM '$i/$totalCount' with domainName '$domainName'.";
    if $DEBUG;then
      addParam="--log $vmLogFile"
    else
      addParam="";
    fi
    output=$(virsh $VIRSH_OPTS $addParam shutdown $domainName 2>&1);
    logDebugMsg "virsh output:\n$output";
    
    # wait until shutdown status is reached
    timeOut=false;
    while [ -n "$(virsh list --all | grep ' $domainName ' | grep -iE 'shut off|ausgeschaltet')" ]; do
      
      # wait a moment before checking again
      logTraceMsg "Waiting for VM '$i/$totalCount' with domainName '$domainName' to shutdown..";
      sleep 2;
      
      # soft timeout reached ?
      isTimeoutReached $TIMEOUT $startDate true;
      [ $? -eq 0 ] && break;
      
      # cancelled meanwhile ?
      #checkCancelFlag;
    done
    # timeout reached ?
    if $timeOut; then
      # clean shut down finished
      msg="VM '$i/$totalCount' with domainName '$domainName', timeout \
of '$TIMEOUT' sec has been reached while waiting for shutdown to finish.";
      indicateRemoteError "$lockFile" "$msg";
    else
      # clean shut down finished
      logDebugMsg "VM '$i/$totalCount' with domainName '$domainName' has been \
shutdown or timeout of '$TIMEOUT' sec has been reached.";
    fi
  fi
  
  # destroy libvirt domain
  logDebugMsg "Destroying VM '$i/$totalCount' with domainName '$domainName'.";
  if $DEBUG;then
    addParam="--log $vmLogFile"
  else
    addParam="";
  fi
  output=$(virsh $VIRSH_OPTS $addParam destroy $domainName 2>&1);
  logDebugMsg "virsh output:\n$output";
  
  logDebugMsg "VM '$i/$totalCount' with domainName '$domainName' has been clean up.";
  
  # remove lock file
  logDebugMsg "Removing lock file for virsh domain name: '$domainName'.";
  rm -f "$lockFile";
  
  # done
  return 0;
}


#---------------------------------------------------------
#
# Abort function that is called by the (global) signal trap.
#
_abort() { # it should not happen that we reach this function, but in case..
  logWarnMsg "Canceling job execution.";
}



#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

# debug log
logDebugMsg "************* BEGIN OF JOB EPILOGUE.PARALLEL ****************";

# ensure that we do not loose anything for debug.log
copyOutputStreams;

# clean up all guests related to the job
cleanUpVMs;
res=$?;

# debug log
logDebugMsg "************** END OF JOB EPILOGUE.PARALLEL ****************";

# print the consumed time in debug mode
runTimeStats;

# done
exit $res;

