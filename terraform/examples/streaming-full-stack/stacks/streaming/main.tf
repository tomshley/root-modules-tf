# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Streaming Stack
#
# This stack creates the Confluent Cloud streaming boundary.
# Topics are infrastructure-owned; workloads consume via access contracts.
#
# Profile Support:
# - commercial_managed: Full Confluent Cloud managed streaming
# - gov_hybrid: Scaffold for future hybrid deployment
#
# No resources are created when confluent_config = null.
