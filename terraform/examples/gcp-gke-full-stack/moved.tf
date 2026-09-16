moved {
  from = module.cluster.google_compute_network.gke_network
  to   = module.network.google_compute_network.gke_network
}

moved {
  from = module.cluster.google_compute_subnetwork.gke_subnet
  to   = module.network.google_compute_subnetwork.gke_subnet
}
