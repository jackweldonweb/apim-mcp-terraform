variable "api_management_name" {
  description = "Name of the existing APIM instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the existing APIM instance."
  type        = string
}

variable "application_insights_id" {
  description = "Resource ID of the Application Insights instance to receive APIM telemetry."
  type        = string
}

variable "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key.  Mark this sensitive in the calling module."
  type        = string
  sensitive   = true
}

variable "application_insights_name" {
  description = "Name used for the APIM logger resource that targets Application Insights."
  type        = string
}

