variable "do_token" {}

variable "faasd-name" {
  default = "faasd"
}

variable "ssh_pub_file" {
  default = "../ssh/faasd.pub"
}

variable "region" {
  default = "fra1"
}

variable "size" {
  default = "s-2vcpu-4gb"
}