# GKE Cluster for NanoClaw Enterprise
# Private cluster with multiple node pools for orchestrator and agent workloads

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "us-central1"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "prod"
}

variable "network_name" {
  type        = string
  description = "VPC network name"
}

variable "subnet_name" {
  type        = string
  description = "Subnet name for GKE nodes"
}

variable "nanoclaw_min_nodes" {
  type        = number
  description = "Minimum nodes in nanoclaw pool"
  default     = 1
}

variable "nanoclaw_max_nodes" {
  type        = number
  description = "Maximum nodes in nanoclaw pool"
  default     = 50
}

variable "agent_min_nodes" {
  type        = number
  description = "Minimum nodes in agent pool"
  default     = 0
}

variable "agent_max_nodes" {
  type        = number
  description = "Maximum nodes in agent pool"
  default     = 100
}

# --- GKE Cluster ---

resource "google_container_cluster" "nanoclaw" {
  name     = "nanoclaw-${var.environment}"
  project  = var.project_id
  location = var.region

  # Use separately managed node pools
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_name
  subnetwork = var.subnet_name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster: nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Workload Identity for secure GCP service access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Binary Authorization for container image verification
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY"
  }

  # Cloud Logging and Monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Network policy enforcement
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Maintenance window: 2am-6am UTC on weekdays
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-01T02:00:00Z"
      end_time   = "2026-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    }
  }

  release_channel {
    channel = "STABLE"
  }
}

# --- System Node Pool ---

resource "google_container_node_pool" "system" {
  name     = "system"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.nanoclaw.name

  initial_node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "e2-standard-2"
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot = true
    }

    labels = {
      pool = "system"
    }

    taint {
      key    = "dedicated"
      value  = "system"
      effect = "NO_SCHEDULE"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# --- NanoClaw Orchestrator Node Pool ---

resource "google_container_node_pool" "nanoclaw" {
  name     = "nanoclaw"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.nanoclaw.name

  initial_node_count = var.nanoclaw_min_nodes

  autoscaling {
    min_node_count = var.nanoclaw_min_nodes
    max_node_count = var.nanoclaw_max_nodes
  }

  node_config {
    machine_type = "e2-standard-4"
    disk_size_gb = 100
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot = true
    }

    labels = {
      pool = "nanoclaw"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# --- Agent Execution Node Pool ---
# Nodes for running DinD sidecars that execute agent containers.
# Privileged pods require this dedicated pool.

resource "google_container_node_pool" "agent" {
  name     = "agent"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.nanoclaw.name

  initial_node_count = var.agent_min_nodes

  autoscaling {
    min_node_count = var.agent_min_nodes
    max_node_count = var.agent_max_nodes
  }

  node_config {
    machine_type = "c2-standard-8"
    disk_size_gb = 200
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      pool = "agent"
    }

    # Agent nodes need larger local SSD for Docker layer cache
    local_ssd_count = 1
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# --- Outputs ---

output "cluster_name" {
  value = google_container_cluster.nanoclaw.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.nanoclaw.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.nanoclaw.master_auth[0].cluster_ca_certificate
  sensitive = true
}
