terraform {
  required_version = ">= 1.5.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.0"
    }
  }
}
