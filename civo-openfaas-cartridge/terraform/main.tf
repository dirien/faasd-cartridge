terraform {
  required_providers {
    civo = {
      source = "civo/civo"
      version = "0.10.4"
    }
    local = {
      source = "hashicorp/local"
      version = "2.1.0"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      version = "2.68.0"
    }
  }
  backend "azurerm" {}
}

provider "civo" {
  token = var.token
  region = "NYC1"
}

resource "civo_kubernetes_cluster" "my-cluster" {
  name = var.name
  applications = "-Traefik"
  num_target_nodes = 3
}

resource "local_file" "foo" {
  content = civo_kubernetes_cluster.my-cluster.kubeconfig
  filename = "/root/.kube/config"
}
