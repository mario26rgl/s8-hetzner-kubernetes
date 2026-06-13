terraform {
  required_version = ">= 1.10.1"
  required_providers {
    wireguard = {
      source  = "OJFord/wireguard"
      version = "~> 0.3"
    }
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
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.7"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.8.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.33.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.15.0"
    }
    aws = {
      source = "hashicorp/aws"
      version = "> 6.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.5"
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

provider "aws" {
  region = "eu-central-1"
}

# Prevent provider picking up `GITHUB_TOKEN` env var and trying to authenticate
provider "github" {
  token = ""
}
