terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
      version = "2.1.0"
    }
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "2.10.1"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      version = "2.68.0"
    }
  }
  backend "azurerm" {}
}

provider "digitalocean" {
  token = var.do_token
}

data "template_cloudinit_config" "ubuntu-config" {
  gzip = false
  base64_encode = false

  # Main cloud-config configuration file.
  part {
    content_type = "text/cloud-config"
    content = <<-EOF
      #cloud-config
      users:
        - default

      package_update: true

      packages:
        - apt-transport-https
        - ca-certificates
        - curl
        - gnupg-agent
        - software-properties-common
        - runc

      # Enable ipv4 forwarding, required on CIS hardened machines
      write_files:
        - path: /etc/sysctl.d/enabled_ipv4_forwarding.conf
          content: |
            net.ipv4.conf.all.forwarding=1
      runcmd:
        - curl -sLSf https://github.com/containerd/containerd/releases/download/v1.5.4/containerd-1.5.4-linux-amd64.tar.gz > /tmp/containerd.tar.gz && tar -xvf /tmp/containerd.tar.gz -C /usr/local/bin/ --strip-components=1
        - curl -SLfs https://raw.githubusercontent.com/containerd/containerd/v1.5.4/containerd.service | tee /etc/systemd/system/containerd.service
        - systemctl daemon-reload && systemctl start containerd
        - systemctl enable containerd

        - mkdir -p /opt/cni/bin
        - curl -sSL https://github.com/containernetworking/plugins/releases/download/v0.9.1/cni-plugins-linux-amd64-v0.9.1.tgz | tar -xz -C /opt/cni/bin

        - mkdir -p /go/src/github.com/openfaas/
        - cd /go/src/github.com/openfaas/ && git clone --depth 1 --branch 0.11.4 https://github.com/openfaas/faasd
        - curl -fSLs "https://github.com/openfaas/faasd/releases/download/0.11.4/faasd" --output "/usr/local/bin/faasd" && chmod a+x "/usr/local/bin/faasd"
        - cd /go/src/github.com/openfaas/faasd/ && /usr/local/bin/faasd install
        - systemctl status -l containerd --no-pager
        - journalctl -u faasd-provider --no-pager
        - systemctl status -l faasd-provider --no-pager
        - systemctl status -l faasd --no-pager
        - curl -sSLf https://cli.openfaas.com | sh
        - sleep 60 && journalctl -u faasd --no-pager
        - cat /var/lib/faasd/secrets/basic-auth-password | /usr/local/bin/faas-cli login --password-stdin
      EOF
  }
}

resource "digitalocean_ssh_key" "ssh-key" {
  name = "${var.faasd-name}-ssh"
  public_key = var.ssh_pub_file
}

resource "digitalocean_droplet" "faasd-droplet" {
  image = "ubuntu-20-10-x64"
  name = "${var.faasd-name}-ubuntu"
  region = var.region
  size = var.size
  ssh_keys = [
    digitalocean_ssh_key.ssh-key.fingerprint
  ]
  user_data = data.template_cloudinit_config.ubuntu-config.rendered
}

resource "digitalocean_firewall" "faasd-fw" {
  name = "only-22-80-and-443"

  droplet_ids = [
    digitalocean_droplet.faasd-droplet.id]

  inbound_rule {
    protocol = "tcp"
    port_range = "22"
    source_addresses = [
      "0.0.0.0/0",
      "::/0"]
  }

  inbound_rule {
    protocol = "tcp"
    port_range = "8080"
    source_addresses = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
  outbound_rule {
    protocol = "tcp"
    port_range = "443"
    destination_addresses = [
      "0.0.0.0/0",
      "::/0"]
  }
  outbound_rule {
    protocol = "tcp"
    port_range = "80"
    destination_addresses = [
      "0.0.0.0/0",
      "::/0"]
  }
  outbound_rule {
    protocol = "tcp"
    port_range = "53"
    destination_addresses = [
      "0.0.0.0/0",
      "::/0"]
  }

  outbound_rule {
    protocol = "udp"
    port_range = "53"
    destination_addresses = [
      "0.0.0.0/0",
      "::/0"]
  }

  outbound_rule {
    protocol = "icmp"
    destination_addresses = [
      "0.0.0.0/0",
      "::/0"]
  }
}

output "faasd-private" {
  value = digitalocean_droplet.faasd-droplet.ipv4_address_private
  description = "The private ips of the nodes"
}

output "faasd-public" {
  value = digitalocean_droplet.faasd-droplet.ipv4_address
  description = "The public ips of the nodes"
}
