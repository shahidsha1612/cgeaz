# --- Capstone addition: the KQL tripwire, as code ---
# drift.yml answers "does reality still match the code?" (terraform plan, nightly).
# This answers the other direction: "who is touching reality?" Any successful
# administrative write made by a human through the Azure portal is, by this repo's
# rules ("changes go through the repo, never the portal"), an out-of-band change.
# CLI/Terraform writes are not flagged here because they share the az-cli app ID;
# the drift workflow catches any of those that leave reality different from code.
#
# blast radius: read-only query over the GRC workspace + an email. Changes nothing.
# CSF 2.0: DE.CM (continuous monitoring), DE.AE (adverse event analysis).

locals {
  workspace_id  = data.terraform_remote_state.foundation.outputs.log_analytics_workspace_id
  workspace_rg  = split("/", local.workspace_id)[4]
  portal_app_id = "c44b4083-3bb0-49c1-b47d-974e53cbdf3c" # Azure Portal (first-party, fixed in every tenant)
}

resource "azurerm_monitor_action_group" "grc_owner" {
  name                = "ag-grc-owner"
  resource_group_name = local.workspace_rg
  short_name          = "grcowner"

  email_receiver {
    name                    = "grc-owner"
    email_address           = var.owner_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "portal_tripwire" {
  name                 = "grc-tripwire-portal-writes"
  display_name         = "GRC tripwire: out-of-band portal change"
  description          = "A human made an administrative write through the Azure portal. Changes must go through the repo."
  resource_group_name  = local.workspace_rg
  location             = var.location
  scopes               = [local.workspace_id]
  severity             = 2
  evaluation_frequency = "PT1H"
  window_duration      = "PT1H"

  criteria {
    query                   = <<-KQL
      AzureActivity
      | where CategoryValue == "Administrative" and ActivityStatusValue == "Success"
      | where OperationNameValue endswith "/WRITE" or OperationNameValue endswith "/DELETE" or OperationNameValue endswith "/ACTION"
      | extend appId = tostring(coalesce(Claims_d.appid, parse_json(Claims).appid))
      | where appId == "${local.portal_app_id}"
      | project TimeGenerated, Caller, OperationNameValue, ResourceGroup, _ResourceId, CorrelationId
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    dimension {
      name     = "Caller"
      operator = "Include"
      values   = ["*"]
    }

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.grc_owner.id]
  }

  tags = {
    env     = "dev"
    purpose = "grc-drift-tripwire"
  }
}

output "tripwire_alert_rule" {
  value = azurerm_monitor_scheduled_query_rules_alert_v2.portal_tripwire.name
}
