terraform {
  required_version = ">= 1.10.1"
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 6.4.0"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.59.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.2"
    }
    ssh = {
      source  = "loafoe/ssh"
      version = "2.7.0"
    }
    deepmerge = {
      source  = "isometry/deepmerge"
      version = "~> 1.0"
    }
  }
  backend "s3" {
    bucket       = "s8-hetzner-k8s-tfstate"
    key          = "backend/terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# Prevent provider picking up `GITHUB_TOKEN` env var and trying to authenticate
provider "github" {
  token = ""
}
