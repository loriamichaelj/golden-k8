# Shared mock data for mock_provider "google" (terraform test). Values only
# where a module indexes into them or the provider schema validates their
# format; everything else is generated. Placeholder project example-project.

mock_data "google_compute_zones" {
  defaults = {
    names = ["us-central1-f", "us-central1-a", "us-central1-b", "us-central1-c"]
  }
}

mock_data "google_client_config" {
  defaults = { project = "example-project", region = "us-central1" }
}

mock_resource "google_compute_network" {
  defaults = {
    id        = "projects/example-project/global/networks/golden-test"
    self_link = "https://www.googleapis.com/compute/v1/projects/example-project/global/networks/golden-test"
  }
}

mock_resource "google_compute_subnetwork" {
  defaults = {
    id        = "projects/example-project/regions/us-central1/subnetworks/golden-test-nodes"
    self_link = "https://www.googleapis.com/compute/v1/projects/example-project/regions/us-central1/subnetworks/golden-test-nodes"
  }
}

mock_resource "google_service_account" {
  defaults = {
    email = "golden-test-nodes@example-project.iam.gserviceaccount.com"
    name  = "projects/example-project/serviceAccounts/golden-test-nodes@example-project.iam.gserviceaccount.com"
  }
}

mock_resource "google_container_cluster" {
  defaults = {
    id       = "projects/example-project/locations/us-central1/clusters/golden-test"
    endpoint = "203.0.113.10"
  }
}
