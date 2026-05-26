output "app_insights_logger_id" {
  description = "Resource ID of the APIM Application Insights logger.  Pass to API-level diagnostic resources that need per-API AI logging."
  value       = azurerm_api_management_logger.app_insights.id
}

output "azure_monitor_logger_id" {
  description = "Constructed resource ID of the APIM built-in Azure Monitor logger.  Use when creating per-API azuremonitor diagnostics."
  value       = local.azure_monitor_logger_id
}
