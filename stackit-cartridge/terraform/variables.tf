variable "pool" {
  default = "floating-net"
}

variable "ssh_pub_file" {
  default = "../ssh/faasd.pub"
}

variable "faasd-name" {
  default = "faasd"
}

variable "flavor" {
  default = "c1.3"
}

variable "subnet-cidr" {
  default = "10.1.10.0/24"
}

variable "ubuntu-image-name" {
  default = "Ubuntu 20.04"
}

variable "auth_url" {}
variable "user_name" {}
variable "password" {}
variable "user_domain_id" {}
variable "region" {}