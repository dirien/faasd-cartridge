terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
      version = "2.1.0"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
      version = "2.2.0"
    }
    openstack = {
      source = "terraform-provider-openstack/openstack"
      version = "1.43.0"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      version = "2.68.0"
    }
  }
  backend "azurerm" {}
}

provider "openstack" {
  auth_url = var.auth_url
  user_name = var.user_name
  password = var.password
  region = var.region
  user_domain_id = var.user_domain_id
}


resource "openstack_compute_keypair_v2" "faasd-kp" {
  name = "${var.faasd-name}-kp"
  public_key = var.ssh_pub_file
}

resource "openstack_networking_network_v2" "faasd-net" {
  name = "${var.faasd-name}-net"
  admin_state_up = "true"
}


resource "openstack_networking_subnet_v2" "faasd-snet" {
  name = "${var.faasd-name}-snet"
  network_id = openstack_networking_network_v2.faasd-net.id
  cidr = var.subnet-cidr
  ip_version = 4
  dns_nameservers = [
    "8.8.8.8",
    "8.8.4.4"]
}

resource "openstack_networking_router_v2" "faasd-router" {
  name = "${var.faasd-name}-router"
  admin_state_up = "true"
  external_network_id = data.openstack_networking_network_v2.floating.id
}

resource "openstack_networking_router_interface_v2" "faasd-ri" {
  router_id = openstack_networking_router_v2.faasd-router.id
  subnet_id = openstack_networking_subnet_v2.faasd-snet.id
}

resource "openstack_networking_secgroup_v2" "faasd-sg" {
  name = "${var.faasd-name}-sec"
  description = "Security group for the Terraform nodes instances"
}

resource "openstack_networking_secgroup_rule_v2" "faasd-22-sgr" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 22
  port_range_max = 22
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.faasd-sg.id
}

resource "openstack_networking_secgroup_rule_v2" "faasd-443-sgr" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 8080
  port_range_max = 8080
  remote_ip_prefix = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.faasd-sg.id
}

data "cloudinit_config" "ubuntu-config" {
  gzip = true
  base64_encode = true

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

resource "openstack_compute_instance_v2" "faasd-vm" {
  name = "${var.faasd-name}-ubuntu"
  flavor_name = var.flavor
  key_pair = openstack_compute_keypair_v2.faasd-kp.name
  security_groups = [
    "default",
    openstack_networking_secgroup_v2.faasd-sg.name
  ]

  user_data = data.cloudinit_config.ubuntu-config.rendered

  network {
    name = openstack_networking_network_v2.faasd-net.name
  }

  block_device {
    uuid = data.openstack_images_image_v2.ubuntu-image.id
    source_type = "image"
    boot_index = 0
    destination_type = "volume"
    volume_size = 10
    delete_on_termination = true
  }
}

resource "openstack_networking_floatingip_v2" "faasd-fip" {
  pool = var.pool
}

resource "openstack_compute_floatingip_associate_v2" "faasd-fipa" {
  instance_id = openstack_compute_instance_v2.faasd-vm.id
  floating_ip = openstack_networking_floatingip_v2.faasd-fip.address
}

output "faasd-private" {
  value = openstack_compute_instance_v2.faasd-vm.access_ip_v4
  description = "The private ips of the nodes"
}

output "faasd-public" {
  value = openstack_networking_floatingip_v2.faasd-fip.address
  description = "The public ips of the nodes"
}
