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
