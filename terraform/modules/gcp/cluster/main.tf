# GCP cluster: a regional GKE cluster (VPC-native, private nodes behind Cloud
# NAT, Workload Identity) with one autoscaled node pool per
# spec.cluster.nodePools entry, running as a dedicated least-privilege node
# service account. GKE's built-in PD CSI driver provides the standard-rwo
# default StorageClass.

locals {
  # From GKE 1.36 a cluster can be created without a default node pool;
  # older versions create one and remove it.
  legacy_default_pool = tonumber(split(".", var.kubernetes_version)[1]) < 36

  # GKE scales regional pools per zone; total_* limits keep min/max cluster-wide.
  node_pools = {
    for p in var.node_pools : p.name => {
      machine_type     = p.instance_type
      total_min        = p.min
      total_max        = p.max
      initial_per_zone = ceil(p.min / length(var.zones))
      labels           = { "golden-k8/pool" = p.name, "golden-k8/size" = p.size }
    }
  }
}

resource "google_service_account" "nodes" {
  account_id   = "${substr(var.name, 0, 23)}-nodes"
  display_name = "GKE nodes for ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  name           = var.name
  location       = var.region
  node_locations = var.zones

  network         = var.network_id
  subnetwork      = var.subnetwork_id
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  min_master_version = var.kubernetes_version
  release_channel {
    channel = "REGULAR"
  }

  # Node pools are managed below, never the default pool.
  remove_default_node_pool = local.legacy_default_pool ? true : null
  initial_node_count       = local.legacy_default_pool ? 1 : 0

  private_cluster_config {
    enable_private_nodes    = var.private_nodes
    enable_private_endpoint = false
  }

  # Authorized networks always on: the endpoint answers the VPC plus only the
  # ranges you list (providerOverrides.masterAuthorizedCidrs).
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block = cidr_blocks.value
      }
    }
  }

  # Dataplane V2 (Cilium) enforces NetworkPolicies, which golden-k8 ships.
  datapath_provider = "ADVANCED_DATAPATH"

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  deletion_protection = var.deletion_protection
}

resource "google_container_node_pool" "this" {
  for_each = local.node_pools

  name           = each.key
  cluster        = google_container_cluster.this.id
  location       = var.region
  node_locations = var.zones

  initial_node_count = each.value.initial_per_zone

  autoscaling {
    total_min_node_count = each.value.total_min
    total_max_node_count = each.value.total_max
    location_policy      = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = each.value.machine_type
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = 50
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = each.value.labels

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    # The autoscaler owns the node count after creation.
    ignore_changes = [initial_node_count]
  }
}
