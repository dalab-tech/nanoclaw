# Cloud Monitoring for NanoClaw Enterprise
# Uptime checks, alert policies, and notification channels

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "notification_email" {
  type        = string
  description = "Email for alert notifications"
}

# --- Notification Channel ---

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "NanoClaw Ops Team"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
}

# --- Alert: Pod Crash Loop ---

resource "google_monitoring_alert_policy" "pod_crash_loop" {
  project      = var.project_id
  display_name = "NanoClaw Pod CrashLoopBackOff"
  combiner     = "OR"

  conditions {
    display_name = "Pod restart count > 5 in 10 minutes"
    condition_threshold {
      filter          = "resource.type = \"k8s_container\" AND metric.type = \"kubernetes.io/container/restart_count\" AND resource.labels.namespace_name = monitoring.regex.full_match(\"tenant-.*\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "600s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    auto_close = "1800s"
  }
}

# --- Alert: High Error Rate in Logs ---

resource "google_monitoring_alert_policy" "high_error_rate" {
  project      = var.project_id
  display_name = "NanoClaw High Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Error log entries > 50 in 5 minutes"
    condition_threshold {
      filter          = "resource.type = \"k8s_container\" AND metric.type = \"logging.googleapis.com/log_entry_count\" AND metric.labels.severity = \"ERROR\""
      comparison      = "COMPARISON_GT"
      threshold_value = 50
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}

# --- Alert: PVC Near Full ---

resource "google_monitoring_alert_policy" "disk_usage" {
  project      = var.project_id
  display_name = "NanoClaw PVC Usage > 80%"
  combiner     = "OR"

  conditions {
    display_name = "Persistent volume usage > 80%"
    condition_threshold {
      filter          = "resource.type = \"k8s_pod\" AND metric.type = \"kubernetes.io/pod/volume/utilization\" AND resource.labels.namespace_name = monitoring.regex.full_match(\"tenant-.*\")"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}

# --- Cloud Monitoring Dashboard ---

resource "google_monitoring_dashboard" "nanoclaw" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "NanoClaw Enterprise Overview"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "Active Tenants (Pods Running)"
          scorecard = {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type = \"k8s_pod\" AND resource.labels.namespace_name = monitoring.regex.full_match(\"tenant-.*\") AND metric.type = \"kubernetes.io/pod/network/received_bytes_count\""
                aggregation = {
                  alignmentPeriod  = "300s"
                  perSeriesAligner = "ALIGN_RATE"
                  crossSeriesReducer = "REDUCE_COUNT"
                }
              }
            }
          }
        },
        {
          title = "Container Agent Executions"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"k8s_container\" AND metric.type = \"kubernetes.io/container/cpu/core_usage_time\" AND resource.labels.container_name = \"dind\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields = ["resource.labels.namespace_name"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Memory Usage by Tenant"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"k8s_container\" AND metric.type = \"kubernetes.io/container/memory/used_bytes\" AND resource.labels.container_name = \"nanoclaw\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                    crossSeriesReducer = "REDUCE_MEAN"
                    groupByFields = ["resource.labels.namespace_name"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Error Rate by Tenant"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type = \"k8s_container\" AND metric.type = \"logging.googleapis.com/log_entry_count\" AND metric.labels.severity = \"ERROR\" AND resource.labels.namespace_name = monitoring.regex.full_match(\"tenant-.*\")"
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields = ["resource.labels.namespace_name"]
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })
}
