variable "log_analytics_workspace_id" {
  type        = string
  description = "Optional override for the Log Analytics Workspace ID to link Container Apps to. When unset, the workspace is resolved from the deployed core resources."
  default     = null
  nullable    = true
}

variable "container_apps_subnet_id" {
  type        = string
  description = "Optional override for the subnet ID to deploy Container Apps into. When unset, the subnet is resolved from the deployed core resources."
  default     = null
  nullable    = true
}
