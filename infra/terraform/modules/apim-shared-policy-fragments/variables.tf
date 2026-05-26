variable "api_management_name" {
  description = "Name of the existing Azure API Management instance."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the existing APIM instance."
  type        = string
}

variable "fragments_path" {
  description = "Absolute path to the directory containing policy fragment XML files. Defaults to the module's own policies/ subdirectory."
  type        = string
  default     = ""
}

variable "named_values_propagation_trigger" {
  description = <<-EOT
    Opaque string whose value changes whenever the APIM named values this module
    depends on are created or updated.  Pass a joined hash of the named value IDs
    from the calling module.  The module waits 120 s after this value changes before
    applying any policy fragment, giving APIM time to propagate the named values to
    all gateway nodes.

    Example (root module):
      named_values_propagation_trigger = join(",", [
        azurerm_api_management_named_value.tenant_id.id,
        azurerm_api_management_named_value.audience.id,
      ])
  EOT
  type        = string
  default     = null
}
