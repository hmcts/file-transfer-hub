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

variable "address_space" {
  type = object({
    vnet           = list(string)
    general_subnet = list(string)
    compute_subnet = list(string)
  })
  description = "Address space values for the vnet and subnets."
}

variable "hub" {
  type = object({
    next_hop_ip_address = string
    vnet_name           = string
    resource_group_name = string
  })
  description = "Values reltated to the hub this spoke should peer to."
}
