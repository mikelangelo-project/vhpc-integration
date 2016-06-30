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


# source the config and common functions
ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source $ABSOLUTE_PATH/snap-common.sh;



#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
#
#
tagTask() {
  
  # check if binaries are available and executable
  if [ ! -x $SNAP_BIN_DIR/snapcontroller ] \
      || [ ! -x $SNAP_BIN_DIR/snapctl ]; then
    logWarnMsg "Snap Monitoring is enabled, but its binaries cannot be found or executed! SNAP_BIN_DIR='$SNAP_BIN_DIR'";
    return -1;
  fi
  
  #FIXME: sth is weird => [DEBUG] Tagging snap monitoring task for job '2359.vsbase2.hlrs.de' with tag 'snapTask-nico-2359.vsbase2.hlrs.de' using format 'experiment:experiment:nr, job_number: 2359.vsbase2.hlrs.de'
  
  # tag the snap monitoring task
  logDebugMsg "Tagging snap monitoring task for job '$JOBID' with tag '$SNAP_TASK_TAG' using format '$SNAP_TAG_FORMAT'";
  logTraceMsg "~~~~~~~~~~Environment_Start~~~~~~~~~~\n$(env)\n~~~~~~~~~~~Environment_End~~~~~~~~~~~";
  
  #
  # dirty quick fix for: 
  #  InfluxB connector opens too many files and dies after ~30min
  #
  ulimit -n 6000; #INTEL uses 6000 successfully
  
  if $DEBUG; then
    # show what's happening
    $SNAP_BIN_DIR/snapcontroller --snapctl $SNAP_BIN_DIR/snapctl ct $SNAP_TASK_TAG |& tee -a $LOG_FILE;
  else
    # be quiet
    $SNAP_BIN_DIR/snapcontroller --snapctl $SNAP_BIN_DIR/snapctl ct $SNAP_TASK_TAG > /dev/null 2>&1;
  fi
  res=$?;
  
  # debug + trace logging
  logDebugMsg "Snap controller's return code: '$res'";
  logTraceMsg "Content of snap's JSON\
\n~~~~~~~~~~~Snap_Temp_File_BEGIN~~~~~~~~~~~\n\
$(cat /tmp/task_${SNAP_TASK_TAG}.json | python -m json.tool)\
\n~~~~~~~~~~~~Snap_Temp_File_END~~~~~~~~~~~~";
  
  # pass on return code
  return $res;
}



#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

# tag task
tagTask;

# pass on return code
exit $?;