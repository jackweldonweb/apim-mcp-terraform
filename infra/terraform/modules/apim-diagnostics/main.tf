terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
  }
}

data "azurerm_api_management" "this" {
  name                = var.api_management_name
  resource_group_name = var.resource_group_name
}

# The Azure Monitor logger is a built-in singleton provisioned automatically
# for every APIM Premium instance.  It has no Terraform resource — reference
# it by its well-known constructed ID.
locals {
  azure_monitor_logger_id = "${data.azurerm_api_management.this.id}/loggers/azuremonitor"
}

# ── Application Insights logger ───────────────────────────────────────────────

resource "azurerm_api_management_logger" "app_insights" {
  name                = var.application_insights_name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  resource_id         = var.application_insights_id

  application_insights {
    instrumentation_key = var.application_insights_instrumentation_key
  }
}

# ── Application Insights diagnostic ──────────────────────────────────────────
#
# body_bytes MUST remain 0 on every request/response block.
# Increasing this value causes APIM to buffer the response so it can capture
# the body — this destroys SSE and Streamable HTTP streams silently.
# Enforce body logging limits via a separate storage export pipeline
# (e.g. Event Hub + Stream Analytics) if you need content auditing.

resource "azurerm_api_management_diagnostic" "app_insights" {
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = var.api_management_name
  api_management_logger_id = azurerm_api_management_logger.app_insights.id

  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"
  operation_name_format     = "Name"

  frontend_request {
    body_bytes     = 0
    headers_to_log = ["Content-Type", "X-Correlation-Id", "Ocp-Apim-Trace-Location"]
  }

  frontend_response {
    body_bytes     = 0
    headers_to_log = ["Content-Type", "X-Correlation-Id", "X-RateLimit-Remaining", "X-RateLimit-Limit"]
  }

  backend_request {
    body_bytes     = 0
    headers_to_log = ["Content-Type"]
  }

  backend_response {
    body_bytes     = 0
    headers_to_log = ["Content-Type"]
  }
}

# ── Azure Monitor diagnostic ──────────────────────────────────────────────────
#
# Azure Monitor receives structured metric events and gateway logs.
# Log Analytics workspace queries (KQL) on this data power dashboards and alerts.
# Same body_bytes = 0 constraint applies — Azure Monitor does not buffer
# responses but the diagnostic framework shares the same buffering path.

resource "azurerm_api_management_diagnostic" "azure_monitor" {
  identifier               = "azuremonitor"
  resource_group_name      = var.resource_group_name
  api_management_name      = var.api_management_name
  api_management_logger_id = local.azure_monitor_logger_id

  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"
  operation_name_format     = "Name"

  frontend_request {
    body_bytes     = 0
    headers_to_log = ["Content-Type", "X-Correlation-Id"]
  }

  frontend_response {
    body_bytes     = 0
    headers_to_log = ["Content-Type", "X-Correlation-Id", "X-RateLimit-Remaining"]
  }

  backend_request {
    body_bytes = 0
  }

  backend_response {
    body_bytes = 0
  }
}
