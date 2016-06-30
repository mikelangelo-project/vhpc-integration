
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
#
##############################################################################
#                                                                            #
# IMPORTANT NOTE:                                                            #
# ===============                                                            #
#  $RUID and $PBS_JOBID is expected to be set.                               #
#                                                                            #
##############################################################################
#
set -o nounset;


#============================================================================#
#                                                                            #
#                               CONSTANTS                                    #
#                             Do not change.                                 #
#============================================================================#

#
# simple flag that indicates the default if not user defined, but use a function in the prologue.parallel whether it'S possible for all nodes (amount of nodeRAM, amount of VM RAM + size VM image)
#
FILESYSTEM_TYPE_SFS='shared'; # shared file system

#
#
#
FILESYSTEM_TYPE_RD='ram'; #ram disk

#
# Colors used for log messages
#
RED='\033[0;31m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
LBLUE='\033[1;34m'
NC='\033[0m' # No Color


#
# RegExpr for supported Standard Linux OS
#
SUPPORTED_STANDARD_LINUX_GUESTS="debian|redhat";

#
# RegExpr for supported container OS
#
SUPPORTED_CONTAINER_OS="osv";

#
# RegExpr for supported OS
#
SUPPORTED_OS="$SUPPORTED_STANDARD_LINUX_GUESTS|$SUPPORTED_CONTAINER_OS";

#
# regex for hostnames of pbs_servers, used for scenario:
#  front-ends and compute nodes have different OS
#
SERVER_HOSTNAME="vsbase2";

#
# path to the real qsub binary on the front-ends
#
REAL_QSUB_ON_SERVER=/opt/torque/current/server/bin/qsub;

#
# path to the real qsub binary on the compute nodes
#
REAL_QSUB_ON_NODES=/opt/torque/current/client/bin/qsub;

#
# FIXME: how to fetch the one from the env ?!
#
TORQUE_HOME="/var/spool/torque";

#
# MAC prefix for VMs.
#
MAC_PREFIX="52:54:00"


#============================================================================#
#                                                                            #
#                          GLOBAL CONFIGURATION                              #
#                                                                            #
#============================================================================#

#
# SCRIPT_BASE_DIR is already set in most cases, just in case it is not..
# it is defined in the profile.d/ file
#
if [ -z ${SCRIPT_BASE_DIR-} ] \
    || [ ! -n "${SCRIPT_BASE_DIR-}" ] \
    || [ ! -d "${SCRIPT_BASE_DIR-}" ]; then
  SCRIPT_BASE_DIR="$(realpath $(dirname ${BASH_SOURCE[0]}))/..";
fi

#
# flag to disable the VM jobs completely, may be useful for troubleshooting
# used by the qsub wrapper only
#
if [ -z ${DISABLE_MIKELANGELO_HPCSTACK-} ]; then
  # not set in environment, apply config value
  DISABLE_MIKELANGELO_HPCSTACK=false;
# else: allow the user to set it in his environment
fi

#
# Regular expression for list of hosts where the VM jobs are disabled for submission
# for job submission, only relevant if DISABLE_MIKELANGELO_HPCSTACK is set to true
#  example value 'frontend[0-9]'
#
DISABLED_HOSTS_LIST="*";


# Indicates whether to run vmPro/Epilogues in parallel
# default is true, useful for debugging only. Do not use in production.
#
PARALLEL=false;

#
# Allows users to define custom images
#
ALLOW_USER_IMAGES=true;

#
# 
#
IMAGE_POOL="";

#
# Amount of core reserved for the host OS
#
HOST_OS_CORE_COUNT=1;

#
# Amout of RAM dedicated to the physical host OS
#
HOST_OS_RAM_MB=2048;

#
# if user images are not allowed, the image must reside in this dir
#
GLOBAL_IMG_DIR="/images";

#
# indicates whether we use DNS to resolve VM IPs dynamically
#  or if we have configured our DNS to use a VM-MAC to Static-IP mapping
#
STATIC_IP_MAPPING=true;

#
# Timeout for remote processes, that boot+destroy VMs
#
TIMEOUT=600;

#
#
#
SHARED_FS_ROOT_DIR="/scratch/.pbs_vm_jobs";

#
# location/prefix for the RAMdisks
#
RAMDISK_DIR_PREFIX="/ramdisk";

#
# forces debug output also to the job's STDOUT file
#
DEBUG_TO_STDOUT=true;


#============================================================================#
#                             Do Not Edit                                    #
#============================================================================#

#
# set the job id (it's in the env when debugging with the help of an
# interactive job, but given as arg when run by Torque or manually
#
noID=false;
if [ ! -z ${PBS_JOBID-} ] && [ -n "$PBS_JOBID" ]; then
  JOBID=$PBS_JOBID;
elif [ ! -z ${JOBID-} ] && [ -n "$JOBID" ]; then
  PBS_JOBID=$JOBID;
elif [ "${JOBID-}" == "NONE_YET" ]; then
  noID=true;
else #PBS_JOBID and JOBID is empty/not set
  echo "PBS_JOBID is not set! usage: $(basename ${BASH_SOURCE[0]}) <jobID>"; # relevant if not executed by Torque, but manually
  exit 1; # abort
fi

if $noID; then
  JOBID="";
elif [ "$PBS_JOBID" != "$JOBID" ]; then
  echo "ERROR: JOBID and PBS_JOBID differ!";
  exit 1;
fi
export PBS_JOBID=$PBS_JOBID;

#
# defines location of generated files and logs for vm-jobs
# do not use $HOME as it is not set everywhere while '~' just works
#
if [ -z ${VM_JOB_DIR_PREFIX-} ]; then
  # may already be set when root-config.sh is loaded, too
  VM_JOB_DIR_PREFIX=~/.pbs_vm_jobs;
fi

#
# Directory to store the job related files that are going to be generated
#
if [ ! -z ${RUID-} ]; then
  RUID=$JOBID;
fi
VM_JOB_DIR="$VM_JOB_DIR_PREFIX/$RUID";

#
# Flag file indicating type of storage to use for the job
#
FILESYSTEM_FLAG_FILE="$VM_JOB_DIR/.filesystype";

#
# Note: in the qsub wrapper, this file does not exist yet
#
USE_RAM_DISK=$(if [ -f "$FILESYSTEM_FLAG_FILE" ] && [ "$(cat $FILESYSTEM_FLAG_FILE)" == "$FILESYSTEM_TYPE_RD" ]; then echo 'true'; else echo 'false'; fi);


#============================================================================#
#                                                                            #
#                            PROCESS ENV VARs                                #
#                             Do Not Edit                                    #
#============================================================================#

#
# TRACE already set in the environment ?
#
if [ -z ${TRACE-} ] || [ "$TRACE" == "__TRACE__" ]; then
  TRACE=false;
fi

#
# TRACE set in the environment ?
# if so enable debugging
#
if [ -n "$TRACE" ] && $TRACE; then
  # if TRACE is enabled, debug is set to true
  DEBUG=true;
elif [ -z ${DEBUG-} ] || [ "$DEBUG" == "__DEBUG__" ]; then
  DEBUG=false;
fi

#
# Should we, in case of debugging enabled, keep the VM running for further
# investigations ?
# NOTE: this blocks until the user cancels with 'ctrl+c' or the walltime is hit
#
if [ -z ${KEEP_VM_ALIVE-} ]; then
  KEEP_VM_ALIVE=false;
fi

#
# Flag file indicating to continue execution.
#
FLAG_FILE_CONTINUE="$VM_JOB_DIR/.continue";

#
# Flag file indicating to cancel execution.
#
CANCEL_FLAG_FILE="$VM_JOB_DIR/.abort";

#
# set globally the SSH options to use (fine for almost all calls)
#

#
SSH_TIMEOUT=5;
# '-n' do not read STDIN
# '-t[t]' Force pseudo-terminal allocation (multiple -t options force tty allocation, even if ssh has no local tty.)
# the -t, is useful for i.e. ssh non-tty mode fails to report pipes correctly ( => [[ -p /dev/stdout ]])
SSH_OPTS="-t -n -o BatchMode=yes -o ConnectTimeout=$SSH_TIMEOUT";
# '-B' batch mode (do not ask for pw)
SCP_OPTS="-B -o ConnectTimeout=$SSH_TIMEOUT";

# debugging enabled ?
if ! $DEBUG; then
  # '-q' quiet
  SSH_OPTS="$SSH_OPTS -q";
  SCP_OPTS="$SCP_OPTS -q";
fi
# parallel mode ?
if $PARALLEL; then
  # '-f' to go to background just before command execution
  SSH_OPTS="$SSH_OPTS -f";
fi

#
#
#
if $DEBUG; then
  VIRSH_OPTS="--debug 3";
elif $TRACE; then
  VIRSH_OPTS="--debug 4";
else
  VIRSH_OPTS="-q";
fi

#
# short name of local host
#
LOCALHOST=$(hostname -s);

#
# Directory that contain all wrapper template files
#
TEMPLATE_DIR="$SCRIPT_BASE_DIR/templates";

#
# Directory that contain all VM template files (domain.xml, metadata)
#
VM_TEMPLATE_DIR="$SCRIPT_BASE_DIR/templates-vm";

#
PINNING_FILE="$VM_JOB_DIR/$LOCALHOST/pinning_frag.txt"; #DO NOT name it .xml

#============================================================================#
#                                                                            #
#                             FILEs AND DIRs                                 #
#                                                                            #
#============================================================================#

#
# VM's XML-definition file, one for each VM per node
#
#used this way: domainXML=$DOMAIN_XML_PREFIX/$computeNode/${parsedParams[$vmNo, NAME]}.xml
DOMAIN_XML_PREFIX=$VM_JOB_DIR;

#
# Shared fs dir that contains locks, one for each VM that is booting/destroyed.
#
LOCKFILES_DIR="$VM_JOB_DIR/locks";

#
# Location of cloud-init log inside VM (required to be in sync with the metadata-template(s))
#
CLOUD_INIT_LOG="/var/log/cloud-init-output.log";

#
#
#
SYS_LOG_FILE_RH="/var/log/messages";

#
#
#
SYS_LOG_FILE_DEBIAN="/var/log/syslog";

#
#
#
SYS_LOG_FILE_OSV="";

#
# Syslog file to fetch from VMs in DEBUG mode.
#
SYS_LOG_FILE=$SYS_LOG_FILE_DEBIAN;

#
# VM job's debug log
#
LOG_FILE="$VM_JOB_DIR/debug.log";

#
# path to shared workspace dir
#
SHARED_FS_JOB_DIR="$SHARED_FS_ROOT_DIR/$JOBID"; #user is not set in all scripts(?)


#
# NOTE: $RUID cannot be used for this as it is used in the root pro/epilogue scripts, too
#
RAMDISK="$RAMDISK_DIR_PREFIX/$JOBID";


#============================================================================#
#                                                                            #
#                                DEFAULTS                                    #
#                                                                            #
#============================================================================#

#
# default file sys type
# either ram or shared fs
#
FILESYSTEM_TYPE_DEFAULT="$FILESYSTEM_TYPE_SFS";

#
# default image in case the user does not request one
#
IMG_DEFAULT="/images/pool/ubuntu_bones-compressed_cloud-3.img";

#
# default distro, MUST match the IMG_DEFAULT
#
DISTRO_DEFAULT="debian";

#
#
#
ARCH_DEFAULT="x86_64";

#
# default for VCPU pinning (en/disabled)
#
VCPU_PINNING_DEFAULT=true;

#
# default amount of vCPUs
#
VCPUS_DEFAULT="8";

#
# Default RAM for VMs in MB
#
RAM_DEFAULT="24576";

#
# default amount of VMs per node
#
VMS_PER_NODE_DEFAULT="1";

#
#
#
DISK_DEFAULT="";

#
# kvm|skvm
#
HYPERVISOR_DEFAULT="kvm";

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
VRDMA_ENABLED_DEFAULT=true;

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
IOCM_ENABLED_DEFAULT=true;

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
IOCM_MIN_CPUS_DEFAULT=1;

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
IOCM_MAX_CPUS_DEFAULT=4;


#============================================================================#
#                                                                            #
#                              QSUB WRAPPER                                  #
#                                                                            #
#============================================================================#


#
# Path to the job submission tool binary 'qsub'.
#
if [[ "$LOCALHOST" =~ $SERVER_HOSTNAME ]]; then
  # path on server
  REAL_QSUB=$REAL_QSUB_ON_SERVER;
else
  # path on compute nodes (may differ)
  REAL_QSUB=$REAL_QSUB_ON_NODES;
fi

#
# Template files
#
SCRIPT_PROLOGUE_TEMPLATE="$TEMPLATE_DIR/vmPrologue.sh"
SCRIPT_PROLOGUE_PARALLEL_TEMPLATE="$TEMPLATE_DIR/vmPrologue.parallel.sh"
SCRIPT_EPILOGUE_TEMPLATE="$TEMPLATE_DIR/vmEpilogue.sh"
SCRIPT_EPILOGUE_PARALLEL_TEMPLATE="$TEMPLATE_DIR/vmEpilogue.parallel.sh"
JOB_SCRIPT_WRAPPER_TEMPLATE="$TEMPLATE_DIR/jobWrapper.sh"

#
#
#
METADATA_TEMPLATE_DEBIAN="$VM_TEMPLATE_DIR/metadata.debian.yaml"
METADATA_TEMPLATE_REDHAT="$VM_TEMPLATE_DIR/metadata.redhat.yaml"
METADATA_TEMPLATE_OSV="$VM_TEMPLATE_DIR/metadata.osv.yaml"

#
# qsub-wrapper output files
#
SCRIPT_PROLOGUE="$VM_JOB_DIR/vmPrologue.sh";
SCRIPT_PROLOGUE_PARALLEL="$VM_JOB_DIR/vmPrologue.parallel.sh";
SCRIPT_EPILOGUE="$VM_JOB_DIR/vmEpilogue.sh";
SCRIPT_EPILOGUE_PARALLEL="$VM_JOB_DIR/vmEpilogue.parallel.sh";
JOB_SCRIPT_WRAPPER="$VM_JOB_DIR/jobWrapper.sh";

#
# subdir on shared fs ($HOME) where the linked user job script is placed
#
VM_JOB_USER_SCRIPT_DIR="$VM_JOB_DIR/userJobScript";

#
# tmp file for job script contents (used for '#PBS' parsing)
#
TMP_JOB_SCRIPT="$VM_JOB_USER_SCRIPT_DIR/jobScript.tmp";

#
# file that collects all '^#PBS ' lines inside the given job
#
JOB_WRAPPER_RES_REQUEST_FILE="$VM_JOB_DIR/pbsResRequests.tmp";

#
# pbs flag parameter that have no value
# 
PBS_FLAG_PARAMETERS="f|F|h|I|n|V|x|X|z";

#
# pbs key/value parameter 
#
PBS_KV_PARAMETERS="a|A|b|c|C|d|D|e|j|k|K|l|L|m|M|N|o|p|P|q|r|S|t|u|v|w|W";


#============================================================================#
#                                                                            #
#              VM [PRO|EPI]LOGUE[.PARALLEL] SCRIPTS                          #
#                                                                            #
#============================================================================#

#
# vm boot log
#
VMLOG_FILE_PREFIX="$VM_JOB_DIR/$LOCALHOST";

#
#
#
DOMAIN_XML_PATH_PREFIX="$VM_JOB_DIR";

#
# construct the template for the provided parameter combination
#
DOMAIN_XML_PATH_NODE="$DOMAIN_XML_PATH_PREFIX/$LOCALHOST";

#
# path prefix for file that contains all VM-IPs
#
VM_IP_FILE_PREFIX="$VM_JOB_DIR";

#
# name of file that contains all VM-IPs
#
VM_IP_FILE_NAME="vmIPs";

#
# path to file that contains all VM-IPs on the local host
#
LOCAL_VM_IP_FILE="$VM_IP_FILE_PREFIX/$LOCALHOST/$VM_IP_FILE_NAME";

#
# Indicates vmPrologue.parallel.sh to abort
#
ABORT_FLAG="$VM_JOB_DIR/.abortFlag";

#
# Lock file that contains started remote processes
#
LOCKFILE="$VM_JOB_DIR/.remoteProcesses";

#
# Indicates failures in parallel processes before lock files can be created
# When lock files are in place we write errors into these so we can identify
# the host and corresponding error msg easily
#
ERROR_FLAG_FILE="$VM_JOB_DIR/.error";


#-----------------------------------------------------------------------------
#
# vmPrologue only
#

#
# vm template with place holders
#
DOMAIN_XML_TEMPLATE_SLG="$VM_TEMPLATE_DIR/domain.slg.xml"; #slg = standard linux guest
DOMAIN_XML_TEMPLATE_OSV="$VM_TEMPLATE_DIR/domain.osv.xml";
DOMAIN_METADATA_XML_TEMPLATE="$VM_TEMPLATE_DIR/domain-fragment-metadata.xml";
DOMAIN_DISK_XML_TEMPLATE="$VM_TEMPLATE_DIR/domain-fragment-disk.xml";
DOMAIN_VRDMA_XML_TEMPLATE="$VM_TEMPLATE_DIR/domain-fragment-vrdma.xml";


#============================================================================#
#                                                                            #
#                               JOB WRAPPER                                  #
#                                                                            #
#============================================================================#

#
# intended  for debug+testing when there is no PBS_NODEFILE set
#
if [ -z ${PBS_NODEFILE-} ] || [ ! -n "$PBS_NODEFILE" ]; then
  PBS_NODEFILE="/var/spool/torque/aux/$JOBID";
fi

#
# VM nodefile, it is required to be called '$PBS_JOBID'
#
PBS_VM_NODEFILE="$VM_JOB_DIR/$JOBID";

#
# directory that is mounted into the VM and contains the PBS_NODEFILE
#
VM_NODE_FILE_DIR="$VM_JOB_DIR/aux";

#
# directory that is mounted into the VM and contains the PBS job environment vars
#
VM_ENV_FILE_DIR="$VM_JOB_DIR";

#
# Dir that contains all job related files that are relevant inside the VMs,
# like the PBS environment file that is host specific
#
VM_DIR="$VM_JOB_DIR/$LOCALHOST";

#
# Prefix for the host env files that are host specific
#
PBS_ENV_FILE_PREFIX="$VM_ENV_FILE_DIR"; #used this way => PBS_ENV_FILE=$PBS_ENV_FILE_PREFIX/$node/vmJobEnviornment



#============================================================================#
#                                                                            #
#                                  IOcm                                      #
#                                                                            #
#============================================================================#

#
# IOcm enabled
#
IOCM_ENABLED=true;

#
# Min amount of dedicated IO cores to be used
#
IOCM_MIN_CORES=0;

#
# Max amount of dedicated IO cores
# recommended amount is calculated by
#  ((allCores [divided by 2 if Hyper-Threading enabled])  minus 1 ForHostOS)
#
IOCM_MAX_CORES=7;

# list of nodes that have the iocm kernel in place
IOCM_NODES="*";

# location of iocm scripts
IOCM_SCRIPT_DIR="$SCRIPT_BASE_DIR/components/iocm";


#============================================================================#
#                                                                            #
#                             DPDK/virtIO/vRDMA                              #
#                                                                            #
#============================================================================#

#
# Indicates whether RoCE is available/enabled (see MIN_IO_CORE_COUNT/MAX_IO_CORE_COUNT)
#
VRDMA_ENABLED=true;

#
# list of nodes supporting RoCE feature for Infiniband
#
VRDMA_NODES='c3tnode0[1,2]';

#
# location of vRDMA management scripts
#
VRDMA_SCRIPT_DIR="$SCRIPT_BASE_DIR/components/vRMDA_p1/";


#============================================================================#
#                                                                            #
#                              SNAP MONITORING                               #
#                                                                            #
#============================================================================#

#
# Indicates whether the snap monitoring is enabled
#
SNAP_MONITORING_ENABLED=true;

#
# location of snap management scripts
#
SNAP_SCRIPT_DIR="$SCRIPT_BASE_DIR/components/snap";
