# State migration from aws-eks-event-journal-db (pre-v1.4.0) to
# aws-eks-aurora-cluster. Consumers that previously used the single-purpose
# module keep their existing resources without destroy/recreate when they
# switch source paths. Consumers that never used the old module are unaffected
# — unmatched `from` addresses are silently ignored by Terraform/OpenTofu.

moved {
  from = aws_db_subnet_group.event_journal
  to   = aws_db_subnet_group.this
}

moved {
  from = aws_security_group.event_journal
  to   = aws_security_group.this
}

moved {
  from = aws_rds_cluster_parameter_group.event_journal
  to   = aws_rds_cluster_parameter_group.this
}

moved {
  from = aws_rds_cluster.event_journal
  to   = aws_rds_cluster.this
}

moved {
  from = aws_rds_cluster_instance.event_journal_writer
  to   = aws_rds_cluster_instance.writer
}

moved {
  from = aws_secretsmanager_secret.event_journal
  to   = aws_secretsmanager_secret.this
}

moved {
  from = aws_secretsmanager_secret_version.event_journal
  to   = aws_secretsmanager_secret_version.this
}

# v1.5.3 — Inline-to-standalone security group rule migration
#
# The inline ingress {} and egress {} blocks were removed from
# aws_security_group.this and replaced with standalone resources:
#   - aws_vpc_security_group_ingress_rule.allowed[*]
#   - aws_vpc_security_group_egress_rule.all
#
# There is no moved {} block for inline→standalone because inline rules are
# not individually addressable in Terraform state. On first apply after
# upgrade the plan will show:
#   ~ aws_security_group.this            (in-place update: inline rules removed)
#   + aws_vpc_security_group_ingress_rule.allowed[0..N]  (created)
#   + aws_vpc_security_group_egress_rule.all              (created)
#
# This is safe — the SG itself is NOT destroyed/recreated, only its inline
# rules are replaced by standalone equivalents.
#
# v1.5.4 — The standalone rule resources now carry an explicit depends_on
# on aws_security_group.this. Without this, OpenTofu resolves the SG ID
# from state (unchanged during an in-place update) and parallelises the
# standalone rule CREATEs with the SG inline-rule revocation, causing
# InvalidPermission.Duplicate errors from the AWS API.
#
# v1.5.6 — Ingress rules switched from count to for_each = toset().
# Resources are keyed by SG ID ("sg-xxx") instead of list index ([0]).
# Existing deployments will see:
#   - aws_vpc_security_group_ingress_rule.allowed[0..N]       (destroyed)
#   + aws_vpc_security_group_ingress_rule.allowed["sg-xxx"]   (created)
# This is a one-time destroy+create cycle (brief connectivity blip).
# Deduplicates automatically and eliminates index-shift races.
