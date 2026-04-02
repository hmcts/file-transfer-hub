variable "hub_subscription_id" {
  type        = string
  description = "The Subscription ID of the Hub Subscription."
}

variable "env" {
  description = "The environment (e.g., dev, test, prod)"
  type        = string
}

variable "builtFrom" {
  type        = string
  description = "GitHub Repo where the IaC is stored."
}

variable "product" {
  type        = string
  description = "The product the infrastructure supports."
}
