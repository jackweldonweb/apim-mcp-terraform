output "policy_fragment_ids" {
  description = "Map of fragment name to azurerm_api_management_policy_fragment resource ID."
  value = {
    validate_entra_token  = azurerm_api_management_policy_fragment.validate_entra_token.id
    sse_hygiene           = azurerm_api_management_policy_fragment.sse_hygiene.id
    rate_limit_per_sub    = azurerm_api_management_policy_fragment.rate_limit_per_sub.id
    quota_per_sub         = azurerm_api_management_policy_fragment.quota_per_sub.id
    emit_tool_call_metric = azurerm_api_management_policy_fragment.emit_tool_call_metric.id
    mcp_error_handling    = azurerm_api_management_policy_fragment.mcp_error_handling.id
  }
}
