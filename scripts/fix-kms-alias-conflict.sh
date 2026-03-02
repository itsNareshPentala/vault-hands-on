#!/bin/bash
# =============================================================================
# fix-kms-alias-conflict.sh
# =============================================================================
# Resolves: AlreadyExistsException when Terraform tries to create a KMS alias
# that already exists in AWS but is not tracked in Terraform state.
#
# This happens when a previous `terraform apply` created the alias but
# `terraform destroy` was not run (or failed), leaving the alias orphaned.
#
# USAGE:
#   chmod +x fix-kms-alias-conflict.sh
#   ./fix-kms-alias-conflict.sh
#
# WHAT IT DOES:
#   Option A (recommended): Delete the orphaned aliases so Terraform can
#                           recreate them with the new unique-suffix naming.
#   Option B:               Import the aliases into Terraform state (only
#                           works if the alias name matches exactly what
#                           Terraform expects — not applicable after the
#                           random_id suffix change).
# =============================================================================

set -euo pipefail

PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
DR_REGION="${DR_REGION:-us-east-2}"
PRIMARY_ALIAS="alias/vault-primary-vault-unseal"
DR_ALIAS="alias/vault-dr-vault-unseal"

echo "=============================================="
echo "KMS Alias Conflict Fix"
echo "=============================================="
echo ""
echo "This script deletes the orphaned KMS aliases that are blocking"
echo "Terraform from creating new ones with unique suffixes."
echo ""
echo "Aliases to delete:"
echo "  [us-east-1] $PRIMARY_ALIAS"
echo "  [us-east-2] $DR_ALIAS"
echo ""

# Confirm before proceeding
read -r -p "Proceed with deletion? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "--- Deleting primary cluster KMS alias ($PRIMARY_REGION) ---"
if aws kms list-aliases --region "$PRIMARY_REGION" \
     --query "Aliases[?AliasName=='$PRIMARY_ALIAS'].AliasName" \
     --output text | grep -q "$PRIMARY_ALIAS"; then
  aws kms delete-alias \
    --alias-name "$PRIMARY_ALIAS" \
    --region "$PRIMARY_REGION"
  echo "  Deleted: $PRIMARY_ALIAS"
else
  echo "  Not found (already deleted or never existed): $PRIMARY_ALIAS"
fi

echo ""
echo "--- Deleting DR cluster KMS alias ($DR_REGION) ---"
if aws kms list-aliases --region "$DR_REGION" \
     --query "Aliases[?AliasName=='$DR_ALIAS'].AliasName" \
     --output text | grep -q "$DR_ALIAS"; then
  aws kms delete-alias \
    --alias-name "$DR_ALIAS" \
    --region "$DR_REGION"
  echo "  Deleted: $DR_ALIAS"
else
  echo "  Not found (already deleted or never existed): $DR_ALIAS"
fi

echo ""
echo "=============================================="
echo "Done. You can now run: terraform apply"
echo ""
echo "NOTE: The new KMS aliases will have a unique random suffix"
echo "(e.g. alias/vault-primary-vault-unseal-a1b2c3d4) to prevent"
echo "this conflict from recurring in future apply/destroy cycles."
echo "=============================================="

# Made with Bob
