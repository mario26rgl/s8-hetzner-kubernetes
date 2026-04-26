locals {
  tenants = { for t in yamldecode(file("${path.module}/../kubernetes/tenants/tenants.yaml")).tenants : t.name => t }
  tags = {
    Repository = "s8-hetzner-kubernetes"
    ManagedBy = "GitHub Actions"
  }
}

resource "aws_secretsmanager_secret" "tenant_user" {
  for_each = local.tenants
  name      = each.value.argocdUser.passwordHashSecretRef.key
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "tenant_user" {
  for_each  = local.tenants
  secret_id = aws_secretsmanager_secret.tenant_user[each.key].id
  secret_string = jsonencode({
    passwordHash = var.mock_password_hash
    passwordMtime = "2026-04-26T20:30:00Z"
  })
}

resource "aws_secretsmanager_secret" "tenant_repo" {
  for_each = local.tenants
  name      = each.value.repoCredentials.secretRef.key
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "tenant_repo" {
  for_each  = local.tenants
  secret_id = aws_secretsmanager_secret.tenant_repo[each.key].id
  secret_string = jsonencode({
    url      = each.value.sourceRepos[0]
    username = "x-access-token"
    password = var.argocd_github_token
  })
}

variable "mock_password_hash" {
  description = "A mock password hash to be used for all tenant users."
  type        = string
}