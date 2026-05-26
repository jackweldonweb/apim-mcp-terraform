# Remote state — Azure Blob Storage.
# Values are supplied at init time via -backend-config or environment variables,
# not hard-coded here, so this file is safe to commit.
#
# Initialise with:
#   terraform init \
#     -backend-config="storage_account_name=<sa>" \
#     -backend-config="container_name=tfstate" \
#     -backend-config="key=apim-mcp/dev/terraform.tfstate" \
#     -backend-config="resource_group_name=<rg>"

terraform {
  backend "azurerm" {}
}
