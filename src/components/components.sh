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
# interated into framework or running separately ?
if [ -d "$ABSOLUTE_PATH/../common" ]; then
  [ -z ${RUID-} } && RUID="";
  source "$ABSOLUTE_PATH/../common/config.sh";
  source "$ABSOLUTE_PATH/../common/functions.sh";
fi

# ensure JOB ID is there
if [ -z ${JOBID-} ]; then
  if [ -z ${PBS_JOBID-} ]; then
    echo "PBS_JOBID is not set!";
    exit 1;
  else
    JOBID=$PBS_JOBID;
  fi
fi

if [ -z ${DEBUG-} ]; then
  DEBUG=false;
fi

if [ -z ${TRACE-} ]; then
  TRACE=false;
fi



