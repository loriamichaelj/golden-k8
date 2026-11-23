# Mocked Google provider (shared mocks in terraform/tests/mocks/gcp): no
# credentials, no API calls, no cost.

mock_provider "google" {
  source = "../../../tests/mocks/gcp"
}

variables {
  name                = "golden-test"
  project_id          = "example-project"
  region              = "us-central1"
  zones               = ["us-central1-a", "us-central1-b", "us-central1-c"]
  kubernetes_version  = "1.36"
  network_id          = "projects/example-project/global/networks/golden-test"
  subnetwork_id       = "projects/example-project/regions/us-central1/subnetworks/golden-test-nodes"
  pods_range_name     = "pods"
  services_range_name = "services"
  private_nodes       = true
  node_pools = [
    { name = "system", size = "small", min = 2, max = 3, instance_type = "e2-standard-2" },
    { name = "apps", size = "medium", min = 1, max = 5, instance_type = "e2-standard-4" },
  ]
}

run "node_pools_from_pools" {
  assert {
    condition     = jsonencode(keys(output.node_pools)) == jsonencode(["apps", "system"])
    error_message = "expected one node pool per pool"
  }
  assert {
    condition = (
      output.node_pools.system.machine_type == "e2-standard-2" &&
      output.node_pools.system.total_min == 2 && output.node_pools.system.total_max == 3 &&
      output.node_pools.system.initial == 1
    )
    error_message = "system pool: small → e2-standard-2, total min 2 / max 3, 1 node per zone to start"
  }
  assert {
    condition     = output.node_pools.apps.machine_type == "e2-standard-4" && output.node_pools.apps.total_max == 5
    error_message = "apps pool: medium → e2-standard-4, total max 5"
  }
  assert {
    condition     = output.node_pools.apps.labels["golden-k8/pool"] == "apps" && output.node_pools.system.labels["golden-k8/size"] == "small"
    error_message = "node pools should carry golden-k8/pool and golden-k8/size labels"
  }
  assert {
    condition     = length(output.node_pools.system.node_locations) == 3
    error_message = "node pools should span the zones"
  }
  assert {
    condition = alltrue([
      for np in google_container_node_pool.this :
      np.node_config[0].service_account == "golden-test-nodes@example-project.iam.gserviceaccount.com" &&
      np.node_config[0].workload_metadata_config[0].mode == "GKE_METADATA" &&
      np.node_config[0].shielded_instance_config[0].enable_secure_boot
    ])
    error_message = "nodes should run as the dedicated service account with Workload Identity metadata and Secure Boot"
  }
}

run "cluster_settings" {
  assert {
    condition     = output.cluster_endpoint == "https://203.0.113.10"
    error_message = "cluster_endpoint should be https:// plus the GKE endpoint"
  }
  assert {
    condition     = google_container_cluster.this.location == "us-central1" && google_container_cluster.this.min_master_version == "1.36"
    error_message = "regional cluster at the requested version"
  }
  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_nodes && !google_container_cluster.this.private_cluster_config[0].enable_private_endpoint
    error_message = "private nodes, public (authorized) endpoint"
  }
  assert {
    condition     = google_container_cluster.this.workload_identity_config[0].workload_pool == "example-project.svc.id.goog"
    error_message = "Workload Identity pool should be <project>.svc.id.goog"
  }
  assert {
    condition     = google_container_cluster.this.ip_allocation_policy[0].cluster_secondary_range_name == "pods"
    error_message = "VPC-native with the pods secondary range"
  }
  assert {
    condition     = google_container_cluster.this.initial_node_count == 0 && google_container_cluster.this.remove_default_node_pool == null
    error_message = "1.36: no default node pool"
  }
  assert {
    condition = (
      length(google_container_cluster.this.master_authorized_networks_config[0].cidr_blocks) == 0 &&
      !google_container_cluster.this.master_authorized_networks_config[0].gcp_public_cidrs_access_enabled
    )
    error_message = "authorized networks always on; by default only the VPC reaches the endpoint"
  }
  assert {
    condition     = google_container_cluster.this.datapath_provider == "ADVANCED_DATAPATH"
    error_message = "Dataplane V2 enforces NetworkPolicies"
  }
  assert {
    condition     = !google_container_cluster.this.master_auth[0].client_certificate_config[0].issue_client_certificate
    error_message = "no client certificates"
  }
  assert {
    condition     = google_project_iam_member.nodes.role == "roles/container.defaultNodeServiceAccount"
    error_message = "the node service account needs only the default node role"
  }
}

run "legacy_version_and_overrides" {
  variables {
    kubernetes_version      = "1.35"
    private_nodes           = false
    master_authorized_cidrs = ["203.0.113.0/24"]
    deletion_protection     = false
  }

  assert {
    condition     = google_container_cluster.this.remove_default_node_pool && google_container_cluster.this.initial_node_count == 1
    error_message = "before 1.36 the default pool is created and removed"
  }
  assert {
    condition     = jsonencode([for b in google_container_cluster.this.master_authorized_networks_config[0].cidr_blocks : b.cidr_block]) == jsonencode(["203.0.113.0/24"])
    error_message = "authorized networks should come from the override"
  }
  assert {
    condition     = !google_container_cluster.this.private_cluster_config[0].enable_private_nodes && !google_container_cluster.this.deletion_protection
    error_message = "public nodes and no deletion protection when asked"
  }
}

run "missing_project" {
  command = plan
  variables { project_id = "" }
  expect_failures = [var.project_id]
}

run "pool_min_over_max" {
  command = plan
  variables {
    node_pools = [{ name = "system", size = "small", min = 4, max = 3, instance_type = "e2-standard-2" }]
  }
  expect_failures = [var.node_pools]
}
