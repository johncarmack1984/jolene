# Lets the release workflow read its signing material from Secrets Manager through GitHub's
# OIDC token, so no long-lived keys live in GitHub: the shared Apple Developer ID secret
# (certificate and the App Store Connect key that notarizes) and Jolene's Sparkle update key.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Shared by every app signed with the team's Developer ID.
data "aws_secretsmanager_secret" "apple_signing" {
  name = "lux/apple-signing"
}

# The EdDSA private key Sparkle checks every update against. The value is put in with
# `aws secretsmanager put-secret-value`, never through terraform, so it stays out of state.
# Losing it means installed copies can't verify updates any more, so it's never deleted
# without a long recovery window.
resource "aws_secretsmanager_secret" "updater_signing_key" {
  name                    = "jolene/updater-signing-key"
  description             = "Sparkle EdDSA private key (base64 seed) that signs Jolene's updates"
  recovery_window_in_days = 30
}

resource "aws_iam_role" "release_signing" {
  name = "jolene-release-signing"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # The subject GitHub's tokens carry for this repo's main, matched whole (immutable ids:
        # 20649979 is johncarmack1984, 1421220829 is jolene): this role reads the key that signs
        # what installed copies install, so no branch or pull request run, and no other
        # repository, may assume it. No wildcard, since IAM's `*` also matches `:`, `/` and `@`,
        # and any repository can choose subject claims that carry these ids. A rename or transfer
        # makes the role refuse until this line has the new prefix and is applied again.
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:johncarmack1984@20649979/jolene@1421220829:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "read_signing_secrets" {
  name = "read-signing-secrets"
  role = aws_iam_role.release_signing.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [data.aws_secretsmanager_secret.apple_signing.arn, aws_secretsmanager_secret.updater_signing_key.arn]
    }]
  })
}

output "release_signing_role_arn" {
  description = "Set as the repo variable AWS_RELEASE_ROLE_ARN."
  value       = aws_iam_role.release_signing.arn
}
