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
}

variable "next_hop_ip_address" {
  type        = string
  description = "The IP address of the next hop for the default route in the route table."
}
