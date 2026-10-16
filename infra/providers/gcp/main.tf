# GCP provider layer for CR-001 (docs/change-request-us-west.md): one dedicated
# tenant, primary us-west1, warm standby us-east1. Exposes the same logical
# outputs as infra/providers/aws so platform and app layers are unchanged.
# STATUS: skeleton — `terraform validate` only; never planned or applied.
# Not yet included: CMEK per region (Google-managed keys here), Cloud DNS
# failover records, GitHub Workload Identity Federation for CI.

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
}

locals {
  regions = {
    primary  = { region = var.primary_region, cidr = var.primary_cidr }
    failover = { region = var.failover_region, cidr = var.failover_cidr }
  }
  labels = { tenant = var.tenant, residency = "us", managed-by = "terraform" }
}

# Residency guard: the project cannot create resources outside the two regions.
resource "google_org_policy_policy" "locations" {
  name   = "projects/${var.project_id}/policies/gcp.resourceLocations"
  parent = "projects/${var.project_id}"
  spec {
    rules {
      values {
        allowed_values = ["in:${var.primary_region}-locations", "in:${var.failover_region}-locations"]
      }
    }
  }
}

# ------------------------------------------------------------------ network

resource "google_compute_network" "this" {
  name                    = "${var.tenant}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  for_each                 = local.regions
  name                     = "${var.tenant}-${each.key}"
  region                   = each.value.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = cidrsubnet(each.value.cidr, 4, 0)
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(each.value.cidr, 1, 1)
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(each.value.cidr, 4, 1)
  }
}

# Private service access for Cloud SQL and Memorystore (no public IPs).
resource "google_compute_global_address" "services" {
  name          = "${var.tenant}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "services" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.services.name]
}

# --------------------------------------------------------------------- GKE

resource "google_container_cluster" "this" {
  for_each = local.regions
  name     = "${var.tenant}-${each.key}"
  location = each.value.region # regional cluster: control plane and nodes across 3 zones

  network                  = google_compute_network.this.id
  subnetwork               = google_compute_subnetwork.this[each.key].id
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = true
  resource_labels          = local.labels

  release_channel { channel = "REGULAR" }
  workload_identity_config { workload_pool = "${var.project_id}.svc.id.goog" }
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = each.key == "primary" ? "172.16.0.0/28" : "172.16.0.16/28"
  }
  # Control plane reachable only from the tenant VPC and the listed operator ranges.
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = each.value.cidr
      display_name = "tenant-vpc"
    }
    dynamic "cidr_blocks" {
      for_each = var.operator_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = "operators"
      }
    }
  }
}

resource "google_container_node_pool" "apps" {
  for_each = local.regions
  name     = "apps"
  cluster  = google_container_cluster.this[each.key].id
  location = each.value.region

  # Standby region runs at minimum size (warm), scaled up during failover.
  autoscaling {
    min_node_count = each.key == "primary" ? var.nodes_min_per_zone : 1
    max_node_count = var.nodes_max_per_zone
  }
  node_config {
    machine_type = var.machine_type
    labels       = local.labels
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config { mode = "GKE_METADATA" }
  }
}

# -------------------------------------------------------------- PostgreSQL

resource "google_sql_database_instance" "primary" {
  name                = "${var.tenant}-pg-primary"
  region              = var.primary_region
  database_version    = "POSTGRES_17"
  deletion_protection = true
  depends_on          = [google_service_networking_connection.services]

  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL" # synchronous standby in another zone
    user_labels       = local.labels
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      location                       = var.primary_region
      backup_retention_settings { retained_backups = 14 }
    }
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.this.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }
  }
}

# Asynchronous cross-region replica. Promotion is a human-approved runbook step.
resource "google_sql_database_instance" "replica" {
  name                 = "${var.tenant}-pg-replica"
  region               = var.failover_region
  database_version     = "POSTGRES_17"
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = true

  replica_configuration { failover_target = false }
  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    user_labels       = local.labels
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.this.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }
  }
}

# ------------------------------------------------------------------- Redis
# One instance per region; Memorystore has no cross-region replication, so the
# standby queue starts empty after a regional failover (see CR job handling).

resource "google_redis_instance" "this" {
  for_each                = local.regions
  name                    = "${var.tenant}-redis-${each.key}"
  region                  = each.value.region
  tier                    = "STANDARD_HA"
  memory_size_gb          = var.redis_memory_gb
  redis_version           = "REDIS_7_2"
  authorized_network      = google_compute_network.this.id
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  labels                  = local.labels
  depends_on              = [google_service_networking_connection.services]
}

# ------------------------------------------------- secrets and image registry

resource "google_secret_manager_secret" "app" {
  secret_id = "${var.tenant}-prod-app-secrets"
  labels    = local.labels
  replication {
    user_managed {
      replicas { location = var.primary_region }
      replicas { location = var.failover_region }
    }
  }
}

resource "google_artifact_registry_repository" "app" {
  location      = "us"
  repository_id = "${var.tenant}-app"
  format        = "DOCKER"
  labels        = local.labels
  docker_config { immutable_tags = true }
}
