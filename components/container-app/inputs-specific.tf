variable "log_analytics_workspace_id" {
  type        = string
  description = "The ID of the Log Analytics Workspace to link Container Apps to."
}

variable "container_apps_subnet_id" {
  type        = string
  description = "The ID of the subnet to deploy Container Apps into."
}

variable "container_app_image" {
  type        = string
  description = "Optional explicit FTPS container image override for this deployment."
  default     = null
}
