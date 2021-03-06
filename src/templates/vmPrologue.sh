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
if [ -z ${PBS_JOBID-} ] \
    || [ ! -n "$PBS_JOBID" ]; then
  # no, assuming debug/test execution
  if [ $# -lt 1 ]; then
    echo "PBS_JOBID is not set! usage: $(basename ${BASH_SOURCE[0]}) <jobID>"; # relevant if not executed by Torque, but manually
    exit 1;
  else
    export PBS_JOBID=$1;
  fi
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
# PBS job owner, will be set in parseParameter
#
JOB_OWNER="";

#
# optional user prologue to wrap
#
PROLOGUE_SCRIPT=__PROLOGUE_SCRIPT__;

#
# optional user vm prologue script
#
VM_PROLOGUE_SCRIPT=__VM_PROLOGUE_SCRIPT__;

#
# the template to use for the MetaData generation
#
METADATA_TEMPLATE=__METADATA_TEMPLATE__;

#
# rank0 VM
#
FIRST_VM="";

#
RES=0;


#============================================================================#
#                                                                            #
#                               VM Parameters                                #
#                                                                            #
#============================================================================#

#
# mandatory VM parameters
#

# name prefix of the VM (libvirt domain name) [mandatory parameter], will be suffixed by the vm-number
NAME="$JOBID";

# operating system image to boot (needs to be known)
IMG=__IMG__;

#
DISTRO=__DISTRO__;

# Absolute path to VM's disk
DISK=__DISK__;


#
# optional VM parameters
#

# [optional] count of vitural cores
VCPUS=__VCPUS__;

# [optional] RAM in MB
RAM=__RAM__;

# [optional] VM's MetaData yaml file provided by the user for additional VM contextualization
METADATA=__METADATA__;

# [optional] VM's cpu architecture, default is x86_64
ARCH=__ARCH__;

# [optional] VM's cpu architecture, default is kvm
HYPERVISOR=__HYPERVISOR__;

# [optional] VM's cpu pinning map
VCPU_PINNING=__VCPU_PINNING__;

VMS_PER_NODE=__VMS_PER_NODE__;

VRDMA=__VRDMA__;

IOCM=__IOCM__;
IOCM_MIN_CORES=__IOCM_MIN_CORES__;
IOCM_MAX_CORES=__IOCM_MAX_CORES__;

#
# keys that needs to be replaced in generateDomainXML (note: it's not all KEYS, some are replaces elsewhere)
#
KEYS="HYPERVISOR UUID RAM VCPUS MAC ARCH IMG METADATA_DISK DISK";

#
# 2D map for the vm paramers (used to replace the place holders in the template)
#
declare -A VM_PARAMS=();


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
#
usage() {
  echo " usage: $(basename ${BASH_SOURCE[0]}) <VMName> <VMImageFile> [<vcpus>] [<ram>] [tmpDiskSize]";
  exit 1;
}


#
# 
#
preConditionCheck() {
  if [ ! -f $PBS_NODEFILE ] \
      || [ ! -r $PBS_NODEFILE ] \
      || [ "" == "$(cat $PBS_NODEFILE)" ]; then
    logErrorMsg "File PBS_NODEFILE '$PBS_NODEFILE' does not exist, is not readable or empty!";
  fi
}


#---------------------------------------------------------
#
# Checks the script parameters that have been received.
#
parseParameter() {
  
  # $1: the JOBID, already processed before including config.sh
  
  #
  # get user name (it's in the env when debugging manually,
  # but given as arg when run by Torque
  #
  if [ -z ${USER-} ]; then
    JOB_OWNER=$2;
  else
    JOB_OWNER=$USER;
  fi
  
  #
  # pbs node file defined in environment ?
  #
  if [ ! -f $PBS_NODEFILE ]; then
    # no, abort with error msg
    logErrorMsg "PBS_NODEFILE is not a file '$PBS_NODEFILE'.";
  fi
}


#---------------------------------------------------------
#
# Validates the parsed VM parameters and puts them into
# the global 2D array $VM_PARAMS.
#
validateParameter() {

  if [ $# -ne 2 ]; then
    logErrorMsg "Function 'validateParameter' called with '$#' arguments, '2' are expected.\nProvided params are: '$@'" 2;
  fi
  
  amountOfNodes=$1;
  vmsPerHost=$2;
  amount=$(($amountOfNodes * $vmsPerHost));
  
  #
  # check parameters and generate missing optional ones
  #
  
  logDebugMsg "Validating VM parameters";
  
  # mandatory parameters
  if [ -z ${NAME-} ] || [ "${NAME-}" == "__NAME__" ]; then
    logErrorMsg "Parameter NAME for VM is undefined.";
  fi
  logTraceMsg "VM parameter NAME is '$NAME'";
  
  if [ -z ${IMG-} ] || [ "${IMG-}" == "__IMG__" ]; then
    logErrorMsg "Parameter IMG for VM is undefined.";
  elif [ ! -f $IMG ] \
      || [ ! -r $IMG ]; then
    logErrorMsg "The image file to boot '$IMG' cannot be read.";
  fi
  logTraceMsg "VM parameter IMG is '$IMG'";
  
  if [ -z ${DISTRO-} ] || [ "${DISTRO-}" == "__DISTRO__" ]; then
    logErrorMsg "Parameter DISTRO for VM is undefined.";
  fi
  logTraceMsg "VM parameter DISTRO is '$DISTRO'";
  
  if [ -z ${RAM-} ] || [ "${RAM-}" == "__RAM__" ]; then
    logErrorMsg "Parameter RAM for VM is undefined.";
  fi
  logTraceMsg "VM parameter RAM is '$RAM'";
  
  if [ -z ${VCPUS-} ] || [ "${VCPUS-}" == "__VCPUS__" ]; then
    logErrorMsg "Parameter VCPUs for VM is undefined.";
  fi
  logTraceMsg "VM parameter VCPUS is '$VCPUS'";
  
  if [ -z ${ARCH-} ] || [ "${ARCH-}" == "__ARCH__" ]; then
    logErrorMsg "Parameter ARCH for VM is undefined.";
  fi
  logTraceMsg "VM parameter ARCH is '$ARCH'";
  
  if [ -z ${HYPERVISOR-} ] || [ "${HYPERVISOR-}" == "__HYPERVISOR__" ]; then
    logErrorMsg "Parameter HYPERVISOR for VM is undefined.";
  fi
  logTraceMsg "VM parameter HYPERVISOR is '$HYPERVISOR'";
  
  if [ -z ${VCPU_PINNING-} ] || [ "${VCPU_PINNING-}" == "__VCPU_PINNING__" ]; then
    logErrorMsg "Parameter VCPU_PINNING for VM is undefined.";
  fi
  logTraceMsg "VM parameter VCPU_PINNING is '$VCPU_PINNING'";
  
  if [ -z ${VMS_PER_NODE-} ] || [ "${VMS_PER_NODE-}" == "__VMS_PER_NODE__" ]; then
    logErrorMsg "Parameter VMS_PER_NODE for VM is undefined.";
  fi
  logTraceMsg "VM parameter VMS_PER_NODE is '$VMS_PER_NODE'";
  
  if [ -z ${VRDMA-} ] || [ "${VRDMA-}" == "__VRDMA__" ]; then
    logErrorMsg "Parameter VRDMA for VM is undefined.";
  fi
  logTraceMsg "VM parameter VRDMA is '$VRDMA'";
  
  if [ -z ${IOCM-} ] || [ "${IOCM-}" == "__IOCM__" ]; then
    logErrorMsg "Parameter IOCM for VM is undefined.";
  fi
  logTraceMsg "VM parameter IOCM is '$IOCM'";
  
  if [ -z ${IOCM_MIN_CORES-} ] || [ "${IOCM_MIN_CORES-}" == "__IOCM_MIN_CORES__" ]; then
    logErrorMsg "Parameter IOCM_MIN_CORES for VM is undefined.";
  fi
  logTraceMsg "VM parameter IOCM_MIN_CORES is '$IOCM_MIN_CORES'";
  
  if [ -z ${IOCM_MAX_CORES-} ] || [ "${IOCM_MAX_CORES-}" == "__IOCM_MAX_CORES__" ]; then
    logErrorMsg "Parameter IOCM_MAX_CORES for VM is undefined.";
  fi
  logTraceMsg "VM parameter IOCM_MAX_CORES is '$IOCM_MAX_CORES'";
  
  if [ -z ${DISK-} ] || [ "${DISK-}" == "__DISK__" ]; then
    logDebugMsg "Optional parameter DISK for VM is undefined.";
    DISK="";
  fi
  logTraceMsg "VM parameter DISK is '$DISK'";
  
  if [ -z ${METADATA-} ] || [ "${METADATA-}" == "__METADATA__" ]; then
    logDebugMsg "Optional parameter METADATA for VM is undefined.";
    METADATA="";
  fi
  logTraceMsg "VM parameter METADATA is '$METADATA'";
  
  if [ -z $PROLOGUE_SCRIPT ] || [ "$PROLOGUE_SCRIPT" == "__PROLOGUE_SCRIPT__" ]; then
    logDebugMsg "Optional parameter PROLOGUE_SCRIPT for VM is undefined.";
    PROLOGUE_SCRIPT="";
  fi
  logTraceMsg "VM parameter PROLOGUE_SCRIPT is '$PROLOGUE_SCRIPT'";
  
  if [ -z $VM_PROLOGUE_SCRIPT ] || [ "$VM_PROLOGUE_SCRIPT" == "__VM_PROLOGUE_SCRIPT__" ]; then
    logDebugMsg "Optional parameter VM_PROLOGUE_SCRIPT for VM is undefined.";
    VM_PROLOGUE_SCRIPT="";
  fi
  logTraceMsg "VM parameter VM_PROLOGUE_SCRIPT is '$VM_PROLOGUE_SCRIPT'";
  
  return 0;
}


#---------------------------------------------------------
#
# Generates the paramter sets for all VMs.
#
generateVMParameterSets() {
  
  
  if [ $# -ne 2 ]; then
    logErrorMsg "Function 'generateVMParameterSets' called with '$#' arguments,\
 '2' are expected.\nProvided params are: '$@'" 2;
  fi
  
  nodes=$1;
  vnodesPerHost=$2;
  
  amountOfNodes=$(echo $nodes | wc -l);
  amountOfVMs=$(($amountOfNodes * $vmsPerHost));
  
  
  #
  #
  #
  total=0;
  logDebugMsg "Creating boot parameters for '$amountOfVMs' VM(s) in total.";
  for computeNode in $(echo $nodes); do
    
    #
    #
    #
    logDebugMsg "Creating boot parameters for '$vmsPerHost' VM(s) on host '$computeNode'.";
    number=1;
    while [ $number -le $vmsPerHost ]; do
      
      # absolute vmNo 
      total=$(($total + $number));
      keyOne="${number}-${computeNode}";
      
      #
      # VM parameters to generate (UUID and MAC)
      #
      
      
      # VM's UUID
      UUID="$(uuidgen)"; # generate
      logTraceMsg "Generated UUID='$UUID' for VM '$number/$vmsPerHost' on node '$computeNode' '$total/$amountOfVMs'.";
      
      # VM's MAC
      MAC=$(generateMAC);
      logTraceMsg "Generated MAC='$MAC' for VM '$number/$vmsPerHost' on node '$computeNode' '$total/$amountOfVMs'.";
      
      #
      # apply
      #
      if $USE_RAM_DISK; then
        destDirName="$RAMDISK/$computeNode";
      else
        destDirName="$SHARED_FS_JOB_DIR/$computeNode";
      fi
      
      # mandatory
      VM_PARAMS[$keyOne, "NAME"]="${NAME}_${number}of${vmsPerHost}";
      VM_PARAMS[$keyOne, "IMG"]="$IMG";
      VM_PARAMS[$keyOne, "DISTRO"]="$DISTRO";
      # generated
      VM_PARAMS[$keyOne, "MAC"]="$MAC";
      VM_PARAMS[$keyOne, "UUID"]="$UUID";
      # optional
      VM_PARAMS[$keyOne, "RAM"]="$RAM";
      VM_PARAMS[$keyOne, "VCPUS"]="$VCPUS";
      # optional persistent user disk cannot be mounted more than once, so it's rank0 only
      if [ $number -eq 0 ]; then
        VM_PARAMS[$keyOne, "DISK"]="$DISK";
      else
        VM_PARAMS[$keyOne, "DISK"]="";
      fi
      # user metadata file
      VM_PARAMS[$keyOne, "METADATA"]="$METADATA";
      # needs to be created first
      VM_PARAMS[$keyOne, "METADATA_DISK"]="";
      VM_PARAMS[$keyOne, "ARCH"]="$ARCH";
      VM_PARAMS[$keyOne, "HYPERVISOR"]="$HYPERVISOR";
      VM_PARAMS[$keyOne, "VCPU_PINNING"]="$VCPU_PINNING";
      
      VM_PARAMS[$keyOne, "VRDMA"]="$VRDMA";
      
      VM_PARAMS[$keyOne, "IOCM"]="$IOCM";
      VM_PARAMS[$keyOne, "IOCM_MIN_CORES"]="$IOCM_MIN_CORES";
      VM_PARAMS[$keyOne, "IOCM_MAX_CORES"]="$IOCM_MAX_CORES";
      
      # increase
      number=$(($number + 1));
    done
    # count
    total=$(($total + $number - 1));
    # logging
    logTraceMsg "VM '$number/$vmsPerHost', Prologue Parameter:\n ${VM_PARAMS[*]}";
    logTraceMsg "Generated for '$vmsPerHost' VM(s) on host '$computeNode' individualized parameter sets, that is '$total/$amountOfVMs' in total.";
  done
  logDebugMsg "Generated for all '$amountOfVMs' VM(s) on all '$amountOfNodes' host individualized parameter sets.";
  return 0;
}


#---------------------------------------------------------
#
# Generates the files for all VMs.
#
generateVMFiles() {
  
  if [ $# -ne 3 ]; then
    logErrorMsg "Function 'generateVMFiles' called with '$#' arguments, '3' are expected.\nProvided params are: '$@'" 2;
  fi
  
  node=$1;
  vnodesPerHost=$2;
  amountOfVMs=$3;
  
  # generate the required meta data
  _generateMetaDataFiles $node $vnodesPerHost $amountOfVMs;
  
  # generate the VM's domain.xml
  _generateDomainXML $node $vnodesPerHost $amountOfVMs;
  
  logDebugMsg "All VM related files (metadata, domainXMLs, etc) have been created.";
}


#---------------------------------------------------------
#
#
#
prepareNode() {
  
  if [ $# -ne 3 ]; then
    logErrorMsg "Function 'prepareNode' called with '$#' arguments, '3' are expected.\nProvided params are: '$@'" 2;
  fi
  
  #
  # params: $node $vnodesPerHost $amountOfVMs
  #
  computeNode=$1; #hostname of physical node
  vnodesPerHost=$2; #number_of_vms_per_host
  amountOfVMs=$3; #total count of vms: number_of_hosts*number_of_vms_per_host
  #
  number=1;
  success=false;
  filesCreatedFlag="$DOMAIN_XML_PATH_PREFIX/$computeNode/.done";
  
  logTraceMsg "Preparing files for '$vnodesPerHost' VM(s) on node '$computeNode' of '$amountOfVMs' total.";
  
  # create the dir that will be shared with VMs
  logDebugMsg "Creating dir '$VM_NODE_FILE_DIR' for VM's nodefile.";
  mkdir -p $VM_NODE_FILE_DIR || logErrorMsg "Failed to create node file dir for VMs!";
  
  logDebugMsg "Staging VM image files for compute node '$computeNode'.";
  
  # canceled meanwhile ?
  checkCancelFlag;
  
  # copy the VM OS image
  logTraceMsg "Copying image file for VM '$number/$vnodesPerHost' on node '$computeNode'.";
  if $PARALLEL; then
    _copyImageFile $computeNode $vnodesPerHost & echo -e "";
  else
    _copyImageFile $computeNode $vnodesPerHost;
  fi
  
  # create flag file to indicate parallel remote processes that we are done
  logDebugMsg "Created/transfered files for all '$vnodesPerHost' VM(s) on host '$node' of '$amountOfVMs' VMs in total.";
  
  # create flag file to indicate node is ready
  logDebugMsg "Creating flag file '$filesCreatedFlag' to indicate host '$node's files are ready.";
  touch "$filesCreatedFlag";
  
  # done
  return 0;
}


#---------------------------------------------------------
#
#
#
_generateMetaDataFiles() {
  
  if [ $# -ne 3 ]; then
    logErrorMsg "Function '_generateMetaDataFiles' called with '$#' arguments, '3' are expected.\nProvided params are: '$@'" 2;
  fi
  
  #
  # params: $node $vnodesPerHost $amountOfVMs
  #
  # the host we generate the metadata for
  computeNode=$1; #hostname of physical node
  vNodesPerHost=$2; #countPerHost=$2; #number_of_vms_per_host
  amountOfVMs=$3; #total count of vms: number_of_hosts*number_of_vms_per_host
  number=1;
  
  logDebugMsg "Generating metadata files for '$vNodesPerHost' VM(s) on host '$computeNode'.";
  
  while [ $number -le $vNodesPerHost ]; do
    
    #
    keyOne="${number}-${computeNode}";
    logTraceMsg "Generating metadata file for VM '$number/$vNodesPerHost' of '$amountOfVMs' total.";
    
    # optional user metadata provided ?
    if [ -n "${VM_PARAMS[$keyOne, 'METADATA']}" ]; then
      logTraceMsg "Metadata user yaml file: '"${VM_PARAMS[$number, "METADATA"]}"'.";
      # check if the metadata file exists
      if [ ! -f "${VM_PARAMS[$keyOne, 'METADATA']}" ] \
          || [ ! -r "${VM_PARAMS[$keyOne, 'METADATA']}" ]; then
        logWarnMsg "User metadata file '${VM_PARAMS[$keyOne, METADATA]}' cannot be read !";
      fi
    fi
    
    # OSv has no metadata image (?)
    if [ -z ${METADATA_TEMPLATE-} ]; then
      logDebugMsg "OSv image assumed since no metadata template is known.";
      # abort here
      return 0; #true
    elif [ "$METADATA_TEMPLATE" == "__METADATA_TEMPLATE__" ]; then
      # abort here with error msg
      logErrorMsg "Something went wrong, the metadata template place-holder is still in place ?!";
    fi
    
    # use hidden tmp file in user's home
    mkdir -p "$VM_JOB_DIR/$computeNode";
    metadataFile="$VM_JOB_DIR/$computeNode/$number-metadata";
    if $USE_RAM_DISK; then
      metamataDiskDir="$RAMDISK/$computeNode";
    else
      metamataDiskDir="$SHARED_FS_JOB_DIR/$computeNode";
    fi
    metaDataDisk="$metamataDiskDir/$number-seed.img";
    
    # get user's group id
    if [ ! -n "$JOB_OWNER" ]; then
      logErrorMsg "\$USER='$JOB_OWNER' is not defined !";
    fi
    groudID=$(getent group $JOB_OWNER | grep -o "[0-9]*");
    
    # copy template
    logDebugMsg "Copying metadata template '$METADATA_TEMPLATE' to '$metadataFile' .";
    if [ ! -f "$METADATA_TEMPLATE" ]; then
      logErrorMsg "Something is wrong, the metadata template '$metadataFile' does not exist!";
    fi
    if [ -f "$metadataFile" ]; then
      logErrorMsg "Something is wrong, the metaData file '$metadataFile' already exists ?!";
    fi
    cp $METADATA_TEMPLATE $metadataFile;
    
    # construct the VM's hostname
    vhostName="v${computeNode}-${number}";
    
    # substitute values
    sed -i "s,__RUID__,$RUID,g" $metadataFile;
    sed -i "s,__HOSTNAME__,$computeNode,g" $metadataFile;
    sed -i "s,__VHOSTNAME__,$vhostName,g" $metadataFile;
    sed -i "s,__GROUP_ID__,$groudID,g" $metadataFile;
    sed -i "s,__USER_ID__,$(id -u),g" $metadataFile; #required for nfs access
    sed -i "s,__USER_NAME__,$JOB_OWNER,g" $metadataFile;
    sed -i "s,__VM_JOB_DIR__,$VM_JOB_DIR,g" $metadataFile;
    sed -i "s,__VM_NODE_FILE_DIR__,$VM_NODE_FILE_DIR,g" $metadataFile;
    sed -i "s,__VM_ENV_FILE_DIR__,$VM_ENV_FILE_DIR/$computeNode/$vhostName,g" $metadataFile;
    sed -i "s,__SCRIPT_BASE_DIR__,$SCRIPT_BASE_DIR/$computeNode/$vhostName,g" $metadataFile;
    
    logTraceMsg "generated METADATA file for VM '$vhostName' number '$number/$vNodesPerHost' of '$amountOfVMs' total.\
\n~~~~~~~~~~~~~~~~~~FILE_BEGIN~~~~~~~~~~~~~~~~~\n$(cat $metadataFile)\n~~~~~~~~~~~~~~~~~~FILE_END~~~~~~~~~~~~~~~~~";
    
    # generate image file from tmpFile [cloud-localds my-seed.img my-user-data my-meta-data]

    logDebugMsg "Creating seed-image '$metaDataDisk' from metadata file '$metadataFile'";
    if [ ! -f "$metadataFile" ]; then
      logErrorMsg "Something is wrong, the metadata file '$metadataFile' does not exist!";
    fi
    if [ -f "$metaDataDisk" ]; then
      logErrorMsg "Something is wrong, the metaDataDisk '$metaDataDisk' already exists ?!";
    fi
    mkdir -p $metamataDiskDir;
    cloud-localds $metaDataDisk $metadataFile;
    res=$?;
    
    # success ?
    if [ $res -ne 0 ]; then
      logErrorMsg "Creating metadata disk '$metaDataDisk' from file '$metadataFile' failed!" \
      & abort;
    fi
    
    # remove tmp file (if not debugging)
    $DEBUG || rm -f $metadataFile;
    
    # store in global array
    VM_PARAMS[$keyOne, "METADATA_DISK"]="$metaDataDisk";
    
    # debug log
    logTraceMsg "METADATA DISK = '${VM_PARAMS[$keyOne, METADATA_DISK]}'; size = '$(du -sh $metaDataDisk | cut -d$'\t' -f1)'\n-----";
    
    # increase counter
    number=$(($number + 1));
  done
  logDebugMsg "Generated Metadata files for '$(($number - 1))' VMs on host '$computeNode'.";
}


#
# 
#
_copyImageFile() {
  
  if [ $# -ne 2 ]; then
    logErrorMsg "Function '_copyImageFile' called with '$#' arguments, '2' are expected.\nProvided params are: '$@'" 2;
  fi
  
  #
  # params: $computeNode $number $vmNo $totalCount;
  #
  computeNode=$1;
  vmsPerHost=$2;
  
  # get src file
  srcFileName="${IMG-}";
  if [ ! -f "$srcFileName" ]; then
    logErrorMsg "Source file '$srcFileName' to stage doesn't exist ?!";
  fi
  
  # get dest dir: ramdisk or shared fs to be used ?
  if $USE_RAM_DISK; then
    destDir="$RAMDISK/$computeNode";
  else
    destDir="$SHARED_FS_JOB_DIR/$computeNode";
  fi
  
  # silent or verbose transfer ?
  if $TRACE; then
    cp_cmd_tmplate="rsync --perms --progress";
  else
    cp_cmd_tmplate="rsync -perms -q";
  fi
  cp_cmd_tmplate="$cp_cmd_tmplate --chmod=ug+rw,o-rw --usermap=*:$JOB_OWNER --groupmap=*:$JOB_OWNER -L $srcFileName";
  
  # build copy cmd(s)
  counter=1;
  cp_cmd="mkdir -p $destDir";
  while [ $counter -le $vmsPerHost ]; do
    # construct filename for dest file
    destFileName="$destDir/${counter}-$(basename $IMG)";
    # file sexists ?
    if [ -f "$destFileName" ]; then
      logWarnMsg "Destination file '$destFileName' to stage already exists ?!";
    fi
    # append copy cmd
    #cp_cmd="$cp_cmd && checkCancelFlag && $cp_cmd_tmplate $destFileName";
    cp_cmd="$cp_cmd && $cp_cmd_tmplate $destFileName";
    # increase counter
    counter=$(($counter + 1));
  done
  
  #
  filesCopiedFlag="$VM_JOB_DIR/$computeNode/.imgCopied";
  
  # finalize cmd
  #cmd=$(echo "$cp_cmd_prefix $cp_cmd; res=\$?; echo \$res > $filesCopiedFlag;");
  cmd="$cp_cmd; res=\$?; echo \$res > $filesCopiedFlag; ls -al $destDir";
  
  # canceled meanwhile ?
  checkCancelFlag;
  
  logDebugMsg "Transferring file '$srcFileName' in total '$vmsPerHost' times to '$destDir'";
  
  # reach out to compute node to execute cmd
  #logTraceMsg "Executing transfer cmd: '$cmd' via SSH one node '$computeNode' ";
  
  # transfer files on remote node to avoid local io-bottleneck in parallel exec)
  output=$(ssh $computeNode "eval $cmd");
  #eval $cmd;
  res=$?;
  logTraceMsg "Output of transfer-cmd on node '$computeNode': $output";
  
  # check return code
  if [ $res -ne 0 ]; then
    logErrorMsg "Copying image file '$srcFileName' to '$destDir' on node '$computeNode' failed!";
  fi
  
  logDebugMsg "Image file '$srcFileName' for '$vmsPerHost' VM(s) on host '$computeNode' transferred to '$destDir'.";
}


#----------------------------------------------------------
#
#
#
_generateDomainXML() {
  
  if [ $# -ne 3 ]; then
    logErrorMsg "Function '_generateDomainXML' called with '$#' arguments, '3' are expected.\nProvided params are: '$@'" 2;
  fi
  
  #
  # params: $node $vnodesPerHost $vmNumber $amountOfVMs
  #
  # the host we generate the metadata for
  computeNode=$1; #hostname of physical node
  countPerHost=$2; #number_of_vms_per_host
  totalCount=$3; #total count of vms: number_of_hosts*number_of_vms_per_host
  
  # get dest dir: ramdisk or shared fs to be used ?
  if $USE_RAM_DISK; then
    destDir="$RAMDISK/$computeNode/";
  else
    destDir="$SHARED_FS_JOB_DIR/$computeNode/";
  fi
  
  #
  number=1;
  
  # generate all domain XML for local VMs
  logDebugMsg "Generating domainXML files for all local VMs.";
  while [ $number -le $countPerHost ]; do #FIXME: number is not vmNo !!! => mapping of vmNo=>conputeNode needed (?)
    
    keyOne="${number}-${computeNode}";
    
    # construct the template for the provided parameter combination (in sync with the VM's name)
    domainXMLfile="$DOMAIN_XML_PREFIX/$computeNode/${VM_PARAMS[$keyOne, NAME]}.xml";
    domainXMLtmpFile="$DOMAIN_XML_PREFIX/$computeNode/${VM_PARAMS[$keyOne, NAME]}.tmp";
    
    logDebugMsg "Generating domainXML file for node '$computeNode' VM '$number/$countPerHost' of '$totalCount' total.";
    
    # copy template to its destination file
    logTraceMsg "Creating tmp file for domainXML '$domainXMLtmpFile'";
    if [ ${VM_PARAMS[$keyOne, 'DISTRO']} == "osv" ]; then
      logTraceMsg "creating OSv domain for VM '$number/$countPerHost' of '$totalCount' total.";
      domainTemplateXML="$DOMAIN_XML_TEMPLATE_OSV";
    elif [[ ${VM_PARAMS[$keyOne, 'DISTRO']} =~ $SUPPORTED_STANDARD_LINUX_GUESTS ]]; then
      logTraceMsg "creating standard linux guest domain for VM '$number/$countPerHost' of '$totalCount' total.";
      domainTemplateXML="$DOMAIN_XML_TEMPLATE_SLG";
    else
      logErrorMsg "Unsupported OS: '${VM_PARAMS[$keyOne, 'DISTRO']}' !";
    fi
    cp $domainTemplateXML $domainXMLtmpFile;
    logTraceMsg "Domain XML file '$domainTemplateXML' copied to '$domainXMLtmpFile'";
    
    # replace the libvirt domain name in the XML
    sed -i "s,__NAME__,${VM_PARAMS[$keyOne, 'NAME']},g" $domainXMLtmpFile;
    
    # is there a metadata seed.img disk ?
    if [ -n "${VM_PARAMS[$keyOne, 'METADATA_DISK']}" ]; then
      logDebugMsg "Generated metadata disk found, merging into domain XML";
      sed -i "s,__METADATA_XML__,$(cat $DOMAIN_METADATA_XML_TEMPLATE | tr '\r\n' ' '),g" $domainXMLtmpFile;
    else
      logErrorMsg "Mandatory metadata disk is missing!";
    fi
    
    # is there a persistent disk ?
    if [ -n "${VM_PARAMS[$keyOne, 'DISK']}" ]; then
      # there should only one for rank0
      [ $number -ne 0 ] && logWarnMsg "HINT: Current VM is not rank0, but it has an user disk defined!";
      logDebugMsg "Optional user disk found, merging into domain XML";
      sed -i "s,__DISK_XML__,$(cat $DOMAIN_DISK_XML_TEMPLATE | tr '\r\n' ' '),g" $domainXMLtmpFile;
    else
      sed -i "s,__DISK_XML__,,g" $domainXMLtmpFile;
    fi
    
    # is core pinning enabled ? (default: no; otherwise file with pinning map is provided )
    if [ -n "${VM_PARAMS[$keyOne, 'VCPU_PINNING']}" ] \
        && ${VM_PARAMS[$keyOne, 'VCPU_PINNING']}; then # enabled
      logDebugMsg "VCPU pinning detected, merging into domain XML.";
      _createCPUpinning "$domainXMLtmpFile" "$number" "$computeNode";
    else # disabled (if not file is given or the file does not exists)
      logDebugMsg "No VCPU pinning provided, removing place-holder from domain XML.";
      sed -i "s,__VCPU_PINNING__,,g" $domainXMLtmpFile;
    fi
    
    # is vRDMA enabled and is it a vRDMA capable node ?
    if [ -n "${VM_PARAMS[$keyOne, 'VRDMA']}" ] \
        && ${VM_PARAMS[$keyOne, 'VRDMA']} \
        && [[ "$LOCALHOST" =~ ^$VRDMA_NODES$ ]]; then
      logDebugMsg "VRDMA requested, merging into domain XML";
      sed -i "s,__VRDMA_XML__,$(cat $DOMAIN_VRDMA_XML_TEMPLATE | tr '\r\n' ' '),g" $domainXMLtmpFile;
    else
      logDebugMsg "VRDMA disabled, removing place-holder from domain XML";
      sed -i "s,__VRDMA_XML__,,g" $domainXMLtmpFile;
    fi
    
    # replace place holders (the ones above are already applied and will be skipped,
    # since the __key__ is not longer there
    for key in $KEYS; do
      if [ "$key" == "IMG" ]; then
        value="$destDir/${number}-$(basename ${VM_PARAMS[$keyOne, $key]})";
      else
        #FIXME: the vmPrologue.parallel complains that the domainXML contains __HYPERVISOR__ !
        value="${VM_PARAMS[$keyOne, $key]}";
      fi
      logTraceMsg "Replacing: key='__${key}__' with value='$value' in domainXML file '$domainXMLtmpFile'.";
      sed -i "s,__${key}__,$value,g" $domainXMLtmpFile;
    done
    
    #
    # replace place holder for VM_NODE_FILE_DIR
    #
    sed -i "s,__VM_NODE_FILE_DIR__,$VM_NODE_FILE_DIR,g" $domainXMLtmpFile;
    sed -i "s,__VM_DIR__,$VM_DIR,g" $domainXMLtmpFile;
    
    # vrdma
    sed -i "s,__HOSTNAME__,$LOCALHOST,g" $domainXMLtmpFile;
    sed -i "s,__JOBID__,$JOBID,g" $domainXMLtmpFile;
    sed -i "s,__VM_NO__,$number,g" $domainXMLtmpFile;
    
    # use the default location no env var like TORQUE_HOME that may point to the wrong location
    # since host may differ from default and thus the guest
    sed -i "s,__DEFAUL_NODE_FILE_DIR__,$VM_NODE_FILE_DIR,g" $domainXMLtmpFile;
    
    # mv the template to its destination
    logDebugMsg "Moving final domain XML file '$domainXMLtmpFile' to destination '$domainXMLfile'.";
    mv $domainXMLtmpFile $domainXMLfile;
    
    logDebugMsg "Domain XML file '$domainXMLfile' created \
for VM '$number/$countPerHost' on node '$computeNode' of '$totalCount' VMs total.";
    logTraceMsg "DomainXML file: '$domainXMLfile':\n\
~~~~~~~~~~~~~FILE_BEGIN~~~~~~~~~~~~~~~~\n$\
(cat $domainXMLfile)\n\
~~~~~~~~~~~~~FILE_END~~~~~~~~~~~~~~~~";
    number=$(($number + 1));
  done
  # get the correct count (+1 before we leave the loop)
  number=$(($number - 1));
  logDebugMsg "Generated '$number' XML domain files for '$countPerHost' VM(s) for node '$computeNode'.";
  return 0;
}


#---------------------------------------------------------
#
# Creates a cpu pinning for the VM's domainXML
#
_createCPUpinning() {
  
  # check amount of params
  if [ $# -ne 3 ]; then
    logErrorMsg "Function '_createCPUpinning' called with '$#' arguments, '3' are expected.\nProvided params are: '$@'" 2;
  fi
  
  # domain XML file, we are merging the pinning into it
  domainXML=$1;
  number=$2;
  computeNode=$3;
  keyOne="${number}-${computeNode}";
  
  if [ ! -f $domainXML ]; then
    logWarnMsg "Parameter '$1' is not a valid (domain XML) file.\n Skipping the CPU pinning feature.";
    return 1;
  fi
  
  # vcpu pinning enabled ?
  if ! ${VM_PARAMS[$keyOne, VCPU_PINNING]}; then # no, skip it
    logTraceMsg "VCPU_PINNING is disabled, skipping generation.";
    sed -i "s,__VCPU_PINNING__,,g" $domainXML;
    return 0;
  elif [ -z ${VM_PARAMS[$keyOne, VCPUS]-} ] \
        || [ ${VM_PARAMS[$keyOne, VCPUS]-} -lt 1 ]; then
    # abort with error
    logErrorMsg "Invalid VCPU parameter for VM '$number' on host '$computeNode': '${VM_PARAMS[$keyOne, VCPUS]-}'";
  fi
  
  # construct XML for pinning
  logTraceMsg "VCPUs parameter is: '${VM_PARAMS[$keyOne, VCPUS]}'.";
  
  # 'i' is an integer counter for the cores we are creating a pinning for
  i=1;
  # amount of cores already pinned
  previousCPUs=0;
  # count all previously pinned cores
  while [ $i -lt $number ]; do
    key="${i}-${computeNode}";
    previousCPUs=$(($previousCPUs + ${VM_PARAMS[$key, VCPUS]}));
    i=$(($i+1));
  done
  logTraceMsg "Previously processed amount of VCPUs for pinning: '$previousCPUs'";
  
  # ensure total count doesn't exceed available cpu count
  cpuCount=$(grep -c ^processor /proc/cpuinfo);
  if [ $cpuCount -lt $previousCPUs ]; then
    logErrorMsg "We have '$cpuCount' on localhost, but pinning requires at \
least '$(($previousCPUs + ${VM_PARAMS[$keyOne, VCPUS]}))'";
  fi
  
  # the pinning (string)
  pinning="";
  # ensure that we create the mapping for the exact count of VCPUs
  i=0;
  while [ $i -lt "${VM_PARAMS[$keyOne, VCPUS]}" ]; do
    line="    <vcpupin vcpu='$i' cpuset='$(($i + $previousCPUs))'/>";
    pinning=$(echo -e "$pinning\n\t$line");
    i=$(($i+1));
  done
  
  # create path to file if not exists, yet
  mkdir -p $(dirname $PINNING_FILE) 2>/dev/null;
  if [ ! -d "$(dirname $PINNING_FILE)" ]; then
    logErrorMsg "Pinning file dir '$(dirname $PINNING_FILE)' does not exist and could not be created!";
  fi
  
  # add line break
  logTraceMsg "VCPU pinning created, merging into domain XML\n-----\n$pinning\n------";
  # complete the pinning xml section
  echo -e "  <vcpu placement='static'>${VM_PARAMS[$keyOne, VCPUS]}</vcpu>\n  <cputune>\n  $pinning\n  </cputune>" > $PINNING_FILE;
  # apply mapping to domain XML
  sed -i "s,__VCPU_PINNING__,$(cat $PINNING_FILE | tr '\r\n' ' '),g" $domainXML;
}


#---------------------------------------------------------
#
#
#
_createNUMApinning() {
  
  # check amount of params
  if [ $# -ne 1 ]; then
    logErrorMsg "Function '_createNUMApinning' called with '$#' arguments, '1' is expected.\nProvided params are: '$@'" 2;
  fi
  
  # domain XML file, we are merging the pinning into it
  domainXML=$1;
  
  if [ ! -f $domainXML ]; then
    logWarnMsg "Parameter '$1' is not a valid (domain XML) file.\n Skipping the NUMA pinning feature.";
    return -1;
  fi
  
  # does the compute node support NUMA ?
  countOfNumaDomains=$(numactl --hardware | grep available | cut -d':' -f2 | cut -d' ' -f1);
  if [ -z $countOfNumaDomains ]; then
    logDebugMsg "No NUMA domains detected. Skipping this feature."
    return -1;
  fi
  
  # https://libvirt.org/formatdomain.html#elementsNUMATuning
  # If placement of vcpu is 'auto', and numatune is not specified, a default numatune with placement 'auto' and mode 'strict' (since libvirt 0.9.3)
   #<numatune>
    # <memory mode="strict" nodeset="1-4,^3"/>
    #<memnode cellid="0" mode="strict" nodeset="1"/>
    #<memnode cellid="2" mode="preferred" nodeset="2"/>
  #</numatune>
}


#---------------------------------------------------------
#
#
#
bootVMsOnHost() {
  
  # check amount of params
  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'bootVMsOnHost' called with '$#' arguments, '1' is expected.\nProvided params are: '$@'" 2;
  fi
  computeNode=$1;
  
  # debug log
  logDebugMsg "Booting VMs on node '$computeNode'.";
  
  # flag file we need
  filesCreatedFlag="$DOMAIN_XML_PATH_PREFIX/$computeNode/.done";
  filesCopiedFlag="$VM_JOB_DIR/$computeNode/.imgCopied";
  
  # in case we run parallel, the files are not in place yet
  logDebugMsg "Waiting for VM related files to be created, copied, etc..";
  logDebugMsg "Lock files to check: '$filesCreatedFlag', '$filesCopiedFlag'.";
  startDate="$(date +%s)";
  
  # wait until prepare nodes is ready (PARALLEL=true)
  while [ ! -f "$filesCreatedFlag" ] || [ ! -f "$filesCopiedFlag" ]; do
    logTraceMsg "Waiting for VM related files to be created, copied, etc..";
    logTraceMsg "Lock files to check: '$filesCreatedFlag', '$filesCopiedFlag'.";
    sleep 1;
    isTimeoutReached $TIMEOUT $startDate;
    checkCancelFlag;
  done
  logDebugMsg "Flag files '$filesCreatedFlag' and '$filesCopiedFlag' found, continuing.";
  $TRACE && output="$(ssh $computeNode \"ls -al $destDir\")" \
  && logTraceMsg "Image files in destination dir '$destDir':\n-----\n$output\n-----";
  
  #
  # start the VM by the help of the vmPrologue.parallel.sh script
  #

  # construct cmd
  cmd="source /etc/profile; exec $(realpath $(dirname ${BASH_SOURCE[0]}))/vmPrologue.parallel.sh $JOBID;";
  logDebugMsg "Trigger boot of VMs on node '$computeNode', cmd: 'ssh $computeNode \"$cmd\"'";
  
  # execute via SSH
  checkCancelFlag;
  ssh $computeNode "$cmd";
  res=$?;
  
  # successful boot init ? (booting still takes place now)
  if [ $res -eq 0 ]; then
    logDebugMsg "Triggering boot of VMs on node '$computeNode' success.";
  else
    # abort with returned exit code
    logErrorMsg "Triggering boot of VMs on node '$computeNode' failed, aborting. Exit code: '$res'." $res;
    # FIXME: due to parallel process we do not abort here as expected !
    touch $ERROR_FLAG_FILE;
  fi
  
  return $res;
}


#---------------------------------------------------------
#
# First rank's first VMs will be merged as first ones into the merged list
#
createVNodeFile() { #FIXME: the vmIPs file do not exist ?!

  #
  # on each node of a job, the running VMs' IPs have been collected previously
  # in vmPrologue.parallel [func: waitForVMtoBecomeAvailable]
  # we merge all these files into a single one
  #

  # check if there was an error or the abort flag is in place
  checkRemoteNodes;
  checkCancelFlag;
  
  logDebugMsg "Using PBS_NODE_FILE='$PBS_NODEFILE' to create virtual PBS_NODEFILE='$PBS_VM_NODEFILE' for all VMs.";
  
  # check if file exists
  [ ! -f $PBS_NODEFILE ] && logErrorMsg "File PBS_NODEFILE '$PBS_NODEFILE' does not exist ?!";
  
  # merge all node vmIPs files into a single one
  for nodeName in $(cat $PBS_NODEFILE | uniq); do
    
    # construct node's VM IPs file name based on all hosts vmIP files that have been created
    # previously to this function, takes place after the boot and wait phase
    vmIPsFile=$VM_IP_FILE_PREFIX/$nodeName/$VM_IP_FILE_NAME;
    
    # ensure it exists
    if [ ! -f "$vmIPsFile" ]; then
      logErrorMsg "Node's '$nodeName' vmIPs file '$vmIPsFile' cannot be found!";
    fi
    # logging
    logTraceMsg "Processing node's '$nodeName' vmIPs file '$vmIPsFile'.\
\n-----start_vm_ip_file------\n$(cat $vmIPsFile)\n------end_vm_ip_file-------";
    
    # merge the local VM IPs into the main one
    vmIPs=$(cat $vmIPsFile);
    if [ ! -n "${vmIPs-}" ]; then
      logErrorMsg "No VMs are running on node '$nodeName' (vm IP file: '$vmIPsFile')." 1>&2;
    fi
    logTraceMsg "Merging all vm IPs from file '$vmIPsFile' into the global virtual \$PBS_VM_NODEFILE";
    cat $vmIPsFile >> $PBS_VM_NODEFILE;
    
  done
  
  # set rank0 VM
  FIRST_VM="$(head -n1 $PBS_VM_NODEFILE)";
  
  # make the VM nodes file available to VMs
  ln -s $PBS_VM_NODEFILE $VM_NODE_FILE_DIR/$JOBID;
  
  # done
  logDebugMsg "PBS node-file '$PBS_VM_NODEFILE' linked to '$VM_NODE_FILE_DIR/$JOBID'.";
  logTraceMsg "PBS_VM_NODEFILE='$PBS_VM_NODEFILE'\n----file_content_start-----\n$(cat $PBS_VM_NODEFILE)\n-----file_content_end-----";
}


#---------------------------------------------------------
#
# Executes user prologue script that can optionally be
# defined by the user via PBS resource requests
#  i.e. 'qsub -l prologue=..,'
#
#
runUserPrologueScript() {
  # user prologue script present ?
  if [ -x  "$PROLOGUE_SCRIPT" ]; then
    logDebugMsg "Running now user's prologue '$PROLOGUE_SCRIPT' ..";
    logDebugMsg "===============PROLOGUE_OUTPUT_BEGIN====================";
    if $DEBUG; then
      $PROLOGUE_SCRIPT |& tee -a $LOG_FILE;
    else
      $PROLOGUE_SCRIPT;
    fi
    exitCode=$?
    logDebugMsg "================PROLOGUE_OUTPUT_END=====================";
    logDebugMsg "Exit Code: '$exitCode'";
    if ! $exitCode; then
      # abort with error code 2
      logErrorMsg "Execution of user's Prologue failed." 2;
    fi
    return $exitCode;
  fi
  return 0;
}


#---------------------------------------------------------
#
# Executes user VM prologue script that can optionally be
# defined by the user via PBS resource requests
#  i.e. 'qsub -vm prologue=..,'
#
runUserVMPrologueScript() {
  # user VM prologue script present ?
  if [ -n "$VM_PROLOGUE_SCRIPT" ] && [ -f "$VM_PROLOGUE_SCRIPT" ]; then
    # present in VM ?
    ensureFileIsAvailableOnHost "$VM_PROLOGUE_SCRIPT" "$FIRST_VM";
    # execute
    logDebugMsg "Running now user's VM prologue '$VM_PROLOGUE_SCRIPT' ..";
    logDebugMsg "==============VM_PROLOGUE_OUTPUT_BEGIN===================";
    if $DEBUG; then
      ssh $SSH_OPTS $FIRST_VM "exec $VM_PROLOGUE_SCRIPT" |& tee -a $LOG_FILE;
    else
      ssh $SSH_OPTS $FIRST_VM "exec $VM_PROLOGUE_SCRIPT";
    fi
    exitCode=$?;
    logDebugMsg "===============VM_PROLOGUE_OUTPUT_END====================";
    logDebugMsg "Exit Code: '$exitCode'";
    if [ ! $RES ]; then
      # abort with error code 2
      logErrorMsg "Execution of user's VM prologue failed." 2;
    fi
    return $exitCode;
  fi
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
#                                    MAIN                                    #
#                                                                            #
#============================================================================#

# debug log
logDebugMsg "***************** BEGIN OF JOB PROLOGUE ********************";

if [ -f "$CANCEL_FLAG_FILE" ]; then
  logDebugMsg "Cancel flag file found, ignoring/removing it.";
  rm -f $CANCEL_FLAG_FILE;
fi

# ensure that we do not loose anything for debug.log
copyOutputStreams;

# process parameters from Torque
parseParameter $@;

# debug log
logDebugMsg "********************* JOB PROLOGUE :: Creating VM files and Booting VMs **************************";

# check if everything is in place
preConditionCheck;

# init variables
nodes=$(cat $PBS_NODEFILE | uniq); # we need uniq, because for each rank there's an entry of that node
vnodesPerHost=$VMS_PER_NODE;
#
nodeCount=$(echo $nodes | wc -l);
amountOfVMs=$(($nodeCount * $vnodesPerHost));

if [ $amountOfVMs -lt 1 ]; then
  logErrorMsg "Less than '1' VM requested.";
fi
logDebugMsg "Physical Nodes ($nodeCount):\n-------\n$nodes\n-----";

# check the place holders and ensure valid values
validateParameter "$nodeCount" "$vnodesPerHost";

# create VM related parameter sets
generateVMParameterSets "$nodes" "$vnodesPerHost";

# debug log
logDebugMsg "++++++++++++++++++ JOB PROLOGUE :: Creating / Staging VM related files for all hosts ++++++++++++++++++";

## for each node
for computeNode in $nodes; do
  
  # generate the VM files based on the parameter sets
  logDebugMsg "------------ Preparing node '$computeNode' (domain XML, copy images, etc) ------------";
  generateVMFiles "$computeNode" "$vnodesPerHost" "$amountOfVMs";
  
  # stage file + boot VMs in parallel ?
  logDebugMsg "Staging files and booting VM(s) on node '$computeNode'.";
  if $PARALLEL; then
    # async #FIXME: bug in bootVMsObHost when running with &
    $(prepareNode "$computeNode" "$vnodesPerHost" "$amountOfVMs" \
        & bootVMsOnHost "$computeNode") &
  else
    # blocking
    prepareNode "$computeNode" "$vnodesPerHost" "$amountOfVMs";
    bootVMsOnHost "$computeNode";
  fi
  
## end of for each node
done

# logging
if $PARALLEL; then
  logDebugMsg "VMs in total being prepared and booted: '$amountOfVMs'";
else
  logDebugMsg "VMs booted in total: '$amountOfVMs'";
fi

# debug log
logDebugMsg "+++++++++++++++++ JOB PROLOGUE :: waiting for all VMs to become available ++++++++++++++++++++";

# wait for (all job related) VMs to become available
waitUntilAllReady;

# abort ?
checkCancelFlag;

# debug log
logDebugMsg "+++++++++++++++++++++++ JOB PROLOGUE :: All VMs to became available ++++++++++++++++++++++++++";

# create job's VM node-file (now all vmIPs are known)
createVNodeFile;

# execute user prologue if there is one
logDebugMsg "Executing user prologue script, if present.";
runUserPrologueScript;
RES=$?;

# execute user VM prologue if there is one
logDebugMsg "Executing user VM prologue script, if present.";
runUserVMPrologueScript;
tmp=$?;
RES=$(($RES + $tmp));

# print debugging output ?
if $DEBUG; then
  # for each node
  for computeNode in $nodes; do
    
    # debug log
    logDebugMsg "\nRunning VMs on compute node '$computeNode' :\
\n-----------\n\
$(ssh $SSH_OPTS $computeNode 'virsh list --all | grep -v shut\ off')\n";
  done
fi

# debug log
logDebugMsg "***************** END OF JOB PROLOGUE ********************";

# print the consumed time in debug mode
runTimeStats;

# done, pass back return code, run the job
exit $RES;
