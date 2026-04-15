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

variable "ftps" {
  type = object({
    certificate_common_name           = optional(string, "ftps.local")
    certificate_key_secret_name       = optional(string, "ftps-certificate-key-pem")
    certificate_secret_name           = optional(string, "ftps-certificate-pem")
    forward_delete_after              = optional(bool, false)
    forward_enabled                   = optional(bool, true)
    forward_interval_seconds          = optional(number, 60)
    listen_port                       = optional(number, 990)
    local_password_secret_name        = optional(string, "ftps-local-password")
    local_upload_user                 = optional(string, "ftpssvc")
    local_user_secret_name            = optional(string, "ftps-local-username")
    passive_port_max                  = optional(number, 1034)
    passive_port_min                  = optional(number, 1024)
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
