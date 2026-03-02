# Artifact Registry for NanoClaw container images

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "us-central1"
}

resource "google_artifact_registry_repository" "nanoclaw" {
  location      = var.region
  project       = var.project_id
  repository_id = "nanoclaw"
  description   = "NanoClaw container images"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
}

output "repository_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.nanoclaw.repository_id}"
}
