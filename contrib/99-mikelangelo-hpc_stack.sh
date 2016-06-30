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

MIKELANGELO_BASE_DIR="/opt/dev/HPC-Integration";

#
# can be removed for production environments,
# contains several tests validating functionality
#
TEST_BASE_DIR="$MIKELANGELO_BASE_DIR/test";

###### DO NOT EDIT BELOW THIS LINE ########

#
# Base directory for all scripts, templates, etc
#
SCRIPT_BASE_DIR="$MIKELANGELO_BASE_DIR/src";

# ensure wrapper is the first match in the PATH
export PATH="$SCRIPT_BASE_DIR:$TEST_BASE_DIR:$PATH";

