# VPC Network for NanoClaw Enterprise
# Private GKE cluster with Cloud NAT for outbound traffic

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
  description = "Environment name (prod, staging)"
  default     = "prod"
}

# --- VPC ---

resource "google_compute_network" "nanoclaw" {
  name                    = "nanoclaw-${var.environment}"
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  name          = "nanoclaw-gke-${var.environment}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.nanoclaw.id
  ip_cidr_range = "10.0.0.0/20"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }

  private_ip_google_access = true
}

# --- Cloud NAT (outbound for private nodes) ---

resource "google_compute_router" "nanoclaw" {
  name    = "nanoclaw-router-${var.environment}"
  project = var.project_id
  region  = var.region
  network = google_compute_network.nanoclaw.id
}

resource "google_compute_router_nat" "nanoclaw" {
  name                               = "nanoclaw-nat-${var.environment}"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.nanoclaw.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- Firewall: allow internal traffic within VPC ---

resource "google_compute_firewall" "allow_internal" {
  name    = "nanoclaw-allow-internal-${var.environment}"
  project = var.project_id
  network = google_compute_network.nanoclaw.id

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]
}

# --- Outputs ---

output "network_id" {
  value = google_compute_network.nanoclaw.id
}

output "network_name" {
  value = google_compute_network.nanoclaw.name
}

output "subnet_id" {
  value = google_compute_subnetwork.gke.id
}

output "subnet_name" {
  value = google_compute_subnetwork.gke.name
}
