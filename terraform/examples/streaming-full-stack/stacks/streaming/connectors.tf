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

# Kafka Connectors (Scaffold)
#
# This file is a seam for future connector deployment resources.
# In this pass, connectors remain catalog-only and are not deployed.
#
# Future implementation will include:
# - confluent_kafka_connector resources
# - Environment-specific configurations
# - Integration with the postgres-sinks catalog
#
# Connectors require a Confluent Connect cluster reference which is
# not available in the current streaming boundary scope.
