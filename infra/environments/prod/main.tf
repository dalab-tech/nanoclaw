# NanoClaw Enterprise - Production Environment
# Brings together all modules to create the complete GCP infrastructure

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  backend "gcs" {
    bucket = "nanoclaw-terraform-state"
    prefix = "prod"
  }
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "us-central1"
}

variable "notification_email" {
  type        = string
  description = "Email for monitoring alerts"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure kubernetes provider after cluster is created
provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

data "google_client_config" "default" {}

# --- Enable required GCP APIs ---

resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# --- Networking ---

module "networking" {
  source = "../../modules/networking"

  project_id  = var.project_id
  region      = var.region
  environment = "prod"

  depends_on = [google_project_service.apis]
}

# --- GKE Cluster ---

module "gke" {
  source = "../../modules/gke-cluster"

  project_id   = var.project_id
  region       = var.region
  environment  = "prod"
  network_name = module.networking.network_name
  subnet_name  = module.networking.subnet_name

  nanoclaw_min_nodes = 1
  nanoclaw_max_nodes = 50
  agent_min_nodes    = 0
  agent_max_nodes    = 100

  depends_on = [module.networking]
}

# --- Artifact Registry ---

module "registry" {
  source = "../../modules/registry"

  project_id = var.project_id
  region     = var.region

  depends_on = [google_project_service.apis]
}

# --- Monitoring ---

module "monitoring" {
  source = "../../modules/monitoring"

  project_id         = var.project_id
  notification_email = var.notification_email

  depends_on = [module.gke]
}

# --- GCS Bucket for Backups ---

resource "google_storage_bucket" "backups" {
  name          = "${var.project_id}-nanoclaw-backups"
  project       = var.project_id
  location      = var.region
  force_destroy = false

  lifecycle_rule {
    condition {
      age = 90 # Delete backups older than 90 days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
}

# --- Outputs ---

output "cluster_name" {
  value = module.gke.cluster_name
}

output "registry_url" {
  value = module.registry.repository_url
}

output "network_name" {
  value = module.networking.network_name
}

# --- Tenant provisioning ---
# Add tenant blocks below. Each block provisions a complete isolated environment.
#
# Example:
#
# module "tenant_acme" {
#   source = "../../modules/tenant"
#
#   project_id         = var.project_id
#   tenant_id          = "acme"
#   tenant_name        = "Acme Corporation"
#   cluster_name       = module.gke.cluster_name
#   region             = var.region
#   registry_url       = module.registry.repository_url
#   nanoclaw_image_tag = "v1.1.3"
#   agent_image_tag    = "v1.1.3"
#   channels           = ["slack", "web"]
#   assistant_name     = "Acme Bot"
#
#   depends_on = [module.gke]
# }
