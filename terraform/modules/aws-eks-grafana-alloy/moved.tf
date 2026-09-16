moved {
  from = helm_release.k8s_monitoring
  to   = module.alloy.helm_release.k8s_monitoring
}
