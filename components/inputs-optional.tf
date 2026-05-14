variable "location" {
  type        = string
  description = "Azure location to deploy into."
  default     = "uksouth"
}

variable "storage_replication_type" {
  description = "The replication type for the Storage Account"
  type        = string
  default     = "LRS"
}

variable "storage_account_kind" {
  description = "The kind of Storage Account"
  type        = string
  default     = "StorageV2"
}

variable "container_app" {
  type = object({
    image                 = optional(string, "hmctsprod.azurecr.io/file-transfer-hub/ftps-server:main")
    cpu                   = optional(number, 2)
    memory                = optional(string, "8Gi")
    workload_profile_type = optional(string, "D4")
  })
  default = {}
}

variable "acr" {
  description = "Azure Container Registry configuration used by the FTPS app for image pulls."
  type = object({
    name                = optional(string, "hmctsprod")
    resource_group_name = optional(string, "rpe-acr-prod-rg")
    subscription_id     = optional(string, "8999dec3-0104-4a27-94ee-6588559729d1")
    login_server        = optional(string, "hmctsprod.azurecr.io")
  })
  default = {}
}

variable "maintenance_mode" {
  description = "When true, all monitoring and alerting resources are disabled. Set in the environment tfvars while the environment is under active development or planned maintenance."
  type        = bool
  default     = false
}

variable "monitoring" {
  description = "Azure Monitor alert configuration for the FTPS container app."
  type = object({
    enabled                      = optional(bool, true)
    alert_email_secret_names     = optional(list(string), ["ftps-alert-email-1", "ftps-alert-email-2", "ftps-alert-email-3"])
    no_replica_alert_frequency   = optional(string, "PT5M")
    no_replica_alert_window_size = optional(string, "PT5M")
    no_replica_alert_severity    = optional(number, 1)
  })
  default = {}
}

variable "ftps" {
  type = object({
    certificate_common_name     = optional(string, "ftps.local")
    certificate_key_vault_id    = optional(string)
    certificate_key_secret_name = optional(string, "ftps-certificate-key-pem")
    certificate_secret_name     = optional(string, "ftps-certificate-pem")
    forward_delete_after        = optional(bool, false)
    forward_enabled             = optional(bool, true)
    forward_interval_seconds    = optional(number, 60)
    forward_targets = optional(list(object({
      name                 = optional(string)
      host                 = optional(string)
      host_secret_name     = optional(string)
      port                 = optional(number, 22)
      remote_dir           = optional(string, ".")
      username_secret_name = optional(string, "ftps-storage-sftp-username")
      password_secret_name = optional(string, "ftps-storage-sftp-password")
      key_vault_id         = optional(string)
    })), [])
    additional_password_secret_name   = optional(string)
    additional_user_secret_name       = optional(string)
    listen_port                       = optional(number, 990)
    local_password_secret_name        = optional(string, "ftps-local-password")
    local_upload_user                 = optional(string, "ftpssvc")
    local_user_secret_name            = optional(string, "ftps-local-username")
    manage_storage_sftp_secret_copies = optional(bool)
    manage_storage_sftp_target        = optional(bool)
    passive_port_min                  = optional(number, 1024)
    passive_port_max                  = optional(number, 1034)
    public_endpoint                   = optional(string, "localhost")
    storage_container_name            = optional(string, "ftps-forward")
    storage_sftp_host                 = optional(string)
    storage_sftp_password_secret_name = optional(string, "ftps-storage-sftp-password")
    storage_sftp_port                 = optional(number, 22)
    storage_sftp_remote_dir           = optional(string, ".")
    storage_sftp_user                 = optional(string, "ftpsvmforwarder")
    storage_sftp_user_secret_name     = optional(string, "ftps-storage-sftp-username")
  })
  default = {}
}
