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

# The cluster and the resources bound to it gained count with
# cluster_enabled, moving existing installs to the [0] addresses rather than
# replacing them.
moved {
  from = aws_eks_cluster.eks_cluster
  to   = aws_eks_cluster.eks_cluster[0]
}

moved {
  from = aws_ec2_tag.eks_managed_sg_karpenter_discovery
  to   = aws_ec2_tag.eks_managed_sg_karpenter_discovery[0]
}

moved {
  from = aws_iam_openid_connect_provider.eks_oidc
  to   = aws_iam_openid_connect_provider.eks_oidc[0]
}
