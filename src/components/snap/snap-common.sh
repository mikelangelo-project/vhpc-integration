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
set -o nounset;

ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$ABSOLUTE_PATH/../components.sh";




# construct the task tag
SNAP_TASK_TAG="snapTask-$USERNAME-$JOBID";

# construct the task tag
SNAP_TASK_TAG="snapTask-$USERNAME-$JOBID";

#
# snap monitoring compute node bin dir
#
SNAP_BIN_DIR="/etc/snap/custom-v0.02/bin";

#
#
#
SNAP_DB_HOST="172.18.2.74";

#
#
#
SNAP_DB_NAME="snap";

#
#
#
SNAP_DB_USER="admin";

#
#
#
SNAP_DB_PASS="admin";

#
#
#
SNAP_TAG_FORMAT="experiment:experiment:nr, job_number: $JOBID";

#
# Interval for update monitoring data
#
SNAP_UPDATE_INTERVALL="2s";

#
# enabled snap plug-ins
#
export METRICS="/intel/linux/iostat/device/sda/avgqu-sz,\
/intel/linux/iostat/device/sda/avgrq-sz,\
/intel/linux/iostat/device/sda/%util,\
/intel/linux/iostat/avg-cpu/%user,\
/intel/linux/iostat/avg-cpu/%idle,\
/intel/linux/iostat/avg-cpu/%system,\
/intel/linux/load/min1,/intel/linux/load/min15,\
/intel/linux/load/min15_rel,/intel/linux/load/min1_rel,\
/intel/linux/load/min5,/intel/linux/load/min5_rel,\
/intel/psutil/net/eth0/bytes_recv,/intel/psutil/net/eth0/bytes_sent,\
/intel/psutil/net/eth1/dropin,\
/intel/psutil/net/eth1/dropout,\
/intel/psutil/net/eth1/errin,\
/intel/psutil/net/eth1/errout,\
/intel/psutil/load/load1,\
/intel/psutil/load/load15,\
/intel/psutil/load/load5,\
/intel/procfs/disk/sda/io_time,\
/intel/procfs/disk/sda/merged_read,\
/intel/procfs/disk/sda/merged_write,\
/intel/procfs/disk/sda/octets_write,\
/intel/procfs/disk/sda/ops_read,\
/intel/procfs/disk/sda/ops_write,\
/intel/procfs/disk/sda/pending_ops,\
/intel/procfs/disk/sda/time_read,\
/intel/procfs/disk/sda/time_write,\
/intel/procfs/disk/sda/weighted_io_time";

export SNAP_BIN_DIR="$SNAP_BIN_DIR";

# define DB connection
export DB_HOST="$SNAP_DB_HOST";
export DB_NAME="$SNAP_DB_NAME";
export DB_USER="$SNAP_DB_USER";
export DB_PASS="$SNAP_DB_PASS";

# define tag format (?)
export TAGS="$SNAP_TAG_FORMAT";

# define bin paths
export SNAPCTL="$SNAP_BIN_DIR/snapctl";
export PATH="$PATH:$SNAP_BIN_DIR";

# define the plugins
export METRICS=$METRIC_PLUGINS;

# define the update interval
export INTERVAL=$SNAP_UPDATE_INTERVALL;



#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#




#---------------------------------------------------------
#
# Ensures all environment variables are in place.
# If not it aborts with an error.
#
checkVRDMAPreconditions() {
  
  if [ -z ${DB_HOST-} ]; then
    logError "Environment variable 'DB_HOST' is not set !";
  fi
  
  if [ -z ${DB_NAME-} ]; then
    logError "Environment variable 'DB_NAME' is not set !";
  fi
  
  if [ -z ${DB_USER-} ]; then
    logError "Environment variable 'DB_USER' is not set !";
  fi
  
  if [ -z ${DB_PASS-} ]; then
    logError "Environment variable 'DB_PASS' is not set !";
  fi
  
  if [ -z ${TAGS-} ]; then
    logError "Environment variable 'TAGS' is not set !";
  fi
  
  if [ -z ${SNAPCTL-} ]; then
    logError "Environment variable 'SNAPCTL' is not set !";
  fi
  
  if [ -z ${METRICS-} ]; then
    logError "Environment variable 'SNAPCTL' is not set !";
  fi
  
  if [ -z ${INTERVAL-} ]; then
    logError "Environment variable 'INTERVAL' is not set !";
  fi
  
  if [ ! -n "$(echo $PATH | grep $SNAPCTL)" ]; then
    logError "Environment variable 'SNAPCTL' is not in 'PATH' !";
  fi
}
  
