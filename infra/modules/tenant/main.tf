# Tenant Provisioning Module
# Creates all GCP + Kubernetes resources for a single NanoClaw tenant

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "tenant_id" {
  type        = string
  description = "Unique tenant identifier (lowercase alphanumeric + hyphens)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.tenant_id))
    error_message = "tenant_id must be 3-31 lowercase alphanumeric characters or hyphens, starting with a letter"
  }
}

variable "tenant_name" {
  type        = string
  description = "Human-readable tenant name"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
}

variable "region" {
  type        = string
  description = "GCP region"
  default     = "us-central1"
}

variable "registry_url" {
  type        = string
  description = "Artifact Registry URL for container images"
}

variable "nanoclaw_image_tag" {
  type        = string
  description = "NanoClaw orchestrator image tag"
  default     = "latest"
}

variable "agent_image_tag" {
  type        = string
  description = "NanoClaw agent image tag"
  default     = "latest"
}

variable "storage_size" {
  type        = string
  description = "PVC size for tenant state"
  default     = "10Gi"
}

variable "cpu_request" {
  type        = string
  description = "CPU request for NanoClaw pod"
  default     = "500m"
}

variable "memory_request" {
  type        = string
  description = "Memory request for NanoClaw pod"
  default     = "1Gi"
}

variable "cpu_limit" {
  type        = string
  description = "CPU limit for NanoClaw pod"
  default     = "2"
}

variable "memory_limit" {
  type        = string
  description = "Memory limit for NanoClaw pod"
  default     = "4Gi"
}

variable "channels" {
  type        = list(string)
  description = "Enabled channels (whatsapp, slack, github, web)"
  default     = ["web"]
}

variable "assistant_name" {
  type        = string
  description = "Assistant display name"
  default     = "Andy"
}

variable "max_concurrent_containers" {
  type        = number
  description = "Max concurrent agent containers"
  default     = 5
}

locals {
  namespace = "tenant-${var.tenant_id}"
  sa_name   = "nanoclaw-${var.tenant_id}"
}

# --- GCP Service Account for this tenant ---

resource "google_service_account" "tenant" {
  project      = var.project_id
  account_id   = local.sa_name
  display_name = "NanoClaw tenant: ${var.tenant_name}"
}

# Grant Secret Manager access (scoped to tenant prefix)
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.tenant.email}"

  condition {
    title      = "tenant-scoped-secrets"
    expression = "resource.name.startsWith(\"projects/${var.project_id}/secrets/nanoclaw-${var.tenant_id}-\")"
  }
}

# Workload Identity binding
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.tenant.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${local.namespace}/${local.sa_name}]"
}

# --- Secret Manager secrets ---

resource "google_secret_manager_secret" "anthropic_api_key" {
  project   = var.project_id
  secret_id = "nanoclaw-${var.tenant_id}-anthropic-api-key"

  replication {
    auto {}
  }

  labels = {
    tenant = var.tenant_id
  }
}

resource "google_secret_manager_secret" "channel_tokens" {
  for_each  = toset(var.channels)
  project   = var.project_id
  secret_id = "nanoclaw-${var.tenant_id}-${each.key}-token"

  replication {
    auto {}
  }

  labels = {
    tenant  = var.tenant_id
    channel = each.key
  }
}

# --- Kubernetes Resources ---

resource "kubernetes_namespace" "tenant" {
  metadata {
    name = local.namespace
    labels = {
      "nanoclaw.io/tenant"     = var.tenant_id
      "nanoclaw.io/managed-by" = "terraform"
    }
    annotations = {
      "nanoclaw.io/tenant-name" = var.tenant_name
    }
  }
}

resource "kubernetes_service_account" "tenant" {
  metadata {
    name      = local.sa_name
    namespace = kubernetes_namespace.tenant.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.tenant.email
    }
  }
}

# --- Resource Quota ---

resource "kubernetes_resource_quota" "tenant" {
  metadata {
    name      = "tenant-quota"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"             = var.cpu_limit
      "requests.memory"          = var.memory_limit
      "limits.cpu"               = "8"
      "limits.memory"            = "16Gi"
      "persistentvolumeclaims"   = "3"
      "pods"                     = "20"
    }
  }
}

# --- Network Policy: isolate tenant ---

resource "kubernetes_network_policy" "isolate" {
  metadata {
    name      = "isolate-tenant"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  spec {
    pod_selector {}

    # Allow all egress (WhatsApp, Slack, Anthropic API need outbound)
    egress {
      {}
    }

    # Only allow ingress from same namespace + ingress controller
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "nanoclaw.io/tenant" = var.tenant_id
          }
        }
      }
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-nginx"
          }
        }
      }
    }

    policy_types = ["Ingress", "Egress"]
  }
}

# --- Persistent Volume Claim ---

resource "kubernetes_persistent_volume_claim" "state" {
  metadata {
    name      = "nanoclaw-state"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "premium-rwo"

    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }
}

# --- NanoClaw Deployment ---

resource "kubernetes_deployment" "nanoclaw" {
  metadata {
    name      = "nanoclaw"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels = {
      app    = "nanoclaw"
      tenant = var.tenant_id
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate" # Single instance per tenant (SQLite + WebSocket)
    }

    selector {
      match_labels = {
        app    = "nanoclaw"
        tenant = var.tenant_id
      }
    }

    template {
      metadata {
        labels = {
          app    = "nanoclaw"
          tenant = var.tenant_id
        }
      }

      spec {
        service_account_name = kubernetes_service_account.tenant.metadata[0].name

        # Schedule on nanoclaw node pool
        node_selector = {
          pool = "nanoclaw"
        }

        # Graceful shutdown: let GroupQueue drain
        termination_grace_period_seconds = 120

        # --- NanoClaw Orchestrator Container ---
        container {
          name  = "nanoclaw"
          image = "${var.registry_url}/nanoclaw:${var.nanoclaw_image_tag}"

          port {
            container_port = 3100
            name           = "web"
          }

          env {
            name  = "INSTANCE_ID"
            value = var.tenant_id
          }
          env {
            name  = "ASSISTANT_NAME"
            value = var.assistant_name
          }
          env {
            name  = "MAX_CONCURRENT_CONTAINERS"
            value = tostring(var.max_concurrent_containers)
          }
          env {
            name  = "CONTAINER_IMAGE"
            value = "${var.registry_url}/nanoclaw-agent:${var.agent_image_tag}"
          }
          env {
            name  = "WEB_CHANNEL_PORT"
            value = "3100"
          }
          env {
            name  = "LOG_LEVEL"
            value = "info"
          }
          # Docker socket from DinD sidecar
          env {
            name  = "DOCKER_HOST"
            value = "tcp://localhost:2375"
          }

          # Secrets from Secret Manager (mounted as env vars via K8s secrets)
          env {
            name = "ANTHROPIC_API_KEY"
            value_from {
              secret_key_ref {
                name = "nanoclaw-secrets"
                key  = "anthropic-api-key"
              }
            }
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          # State volume: SQLite DB, groups/, data/
          volume_mount {
            name       = "state"
            mount_path = "/app/store"
            sub_path   = "store"
          }
          volume_mount {
            name       = "state"
            mount_path = "/app/groups"
            sub_path   = "groups"
          }
          volume_mount {
            name       = "state"
            mount_path = "/app/data"
            sub_path   = "data"
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 3100
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 3100
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        # --- Docker-in-Docker Sidecar ---
        container {
          name  = "dind"
          image = "docker:27-dind"

          security_context {
            privileged = true
          }

          env {
            name  = "DOCKER_TLS_CERTDIR"
            value = "" # Disable TLS for localhost communication
          }

          port {
            container_port = 2375
          }

          resources {
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
            limits = {
              cpu    = "4"
              memory = "8Gi"
            }
          }

          # Docker data on emptyDir (ephemeral, cleaned up with pod)
          volume_mount {
            name       = "docker-data"
            mount_path = "/var/lib/docker"
          }

          # Share state volume so agent containers can access group files
          volume_mount {
            name       = "state"
            mount_path = "/app/store"
            sub_path   = "store"
          }
          volume_mount {
            name       = "state"
            mount_path = "/app/groups"
            sub_path   = "groups"
          }
          volume_mount {
            name       = "state"
            mount_path = "/app/data"
            sub_path   = "data"
          }
        }

        volume {
          name = "state"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.state.metadata[0].name
          }
        }

        volume {
          name = "docker-data"
          empty_dir {
            size_limit = "50Gi"
          }
        }
      }
    }
  }
}

# --- Service ---

resource "kubernetes_service" "nanoclaw" {
  metadata {
    name      = "nanoclaw"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  spec {
    selector = {
      app    = "nanoclaw"
      tenant = var.tenant_id
    }

    port {
      port        = 80
      target_port = 3100
      name        = "web"
    }

    type = "ClusterIP"
  }
}

# --- GCS Backup CronJob ---

resource "kubernetes_cron_job_v1" "backup" {
  metadata {
    name      = "state-backup"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  spec {
    schedule = "0 */6 * * *" # Every 6 hours

    job_template {
      spec {
        template {
          spec {
            service_account_name = kubernetes_service_account.tenant.metadata[0].name

            container {
              name  = "backup"
              image = "google/cloud-sdk:slim"

              command = ["/bin/bash", "-c"]
              args = [
                "gsutil -m rsync -r -d /backup/store gs://${var.project_id}-nanoclaw-backups/${var.tenant_id}/store/ && gsutil -m rsync -r -d /backup/groups gs://${var.project_id}-nanoclaw-backups/${var.tenant_id}/groups/"
              ]

              volume_mount {
                name       = "state"
                mount_path = "/backup/store"
                sub_path   = "store"
                read_only  = true
              }
              volume_mount {
                name       = "state"
                mount_path = "/backup/groups"
                sub_path   = "groups"
                read_only  = true
              }
            }

            restart_policy = "OnFailure"

            volume {
              name = "state"
              persistent_volume_claim {
                claim_name = "nanoclaw-state"
              }
            }
          }
        }
      }
    }
  }
}

# --- Outputs ---

output "namespace" {
  value = kubernetes_namespace.tenant.metadata[0].name
}

output "service_account_email" {
  value = google_service_account.tenant.email
}

output "secret_ids" {
  value = {
    anthropic_api_key = google_secret_manager_secret.anthropic_api_key.secret_id
    channel_tokens    = { for k, v in google_secret_manager_secret.channel_tokens : k => v.secret_id }
  }
}
