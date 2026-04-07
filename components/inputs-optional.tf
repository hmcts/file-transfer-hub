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
