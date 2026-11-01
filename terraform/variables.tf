variable "project_name" {
  description = "Project identifier used in resource naming"
  type        = string
  default     = "atlas-02"
}

variable "environment" {
  description = "Environment identifier (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "centralindia"
}

variable "acr_sku" {
  description = "ACR pricing tier (Basic = cheapest, sufficient for portfolio)"
  type        = string
  default     = "Basic"
}

variable "cost_center" {
  description = "Cost center tag for FinOps attribution"
  type        = string
  default     = "atlas-platform"
}

variable "created_by" {
  description = "Creator tag for resource ownership tracking"
  type        = string
  default     = "terraform"
}