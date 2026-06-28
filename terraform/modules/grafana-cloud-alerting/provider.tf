terraform {
  # optional(...) object attributes with defaults in metric_rules/log_rules.
  required_version = ">= 1.3"

  required_providers {
    grafana = {
      source = "grafana/grafana"
      # >= 2.9.0 : per-rule `notification_settings` (simplified routing; also
      #            requires Grafana 10.4+ on the target instance).
      # <  3.0.0 : the v3 provider renames/relocates several alerting resources;
      #            bump deliberately after re-testing, do not let it float.
      version = ">= 2.9.0, < 3.0.0"
    }
  }
}
