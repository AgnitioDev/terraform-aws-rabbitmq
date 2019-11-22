variable "vpc_id" {
}

variable "ssh_key_name" {
}

variable "name" {
  default = "main"
}

variable "min_size" {
  description = "Minimum number of RabbitMQ nodes"
  default     = 2
}

variable "desired_size" {
  description = "Desired number of RabbitMQ nodes"
  default     = 2
}

variable "max_size" {
  description = "Maximum number of RabbitMQ nodes"
  default     = 2
}

variable "subnet_ids" {
  description = "Subnets for RabbitMQ nodes"
  type        = list(string)
}

variable "nodes_additional_security_group_ids" {
  type    = list(string)
  default = []
}

variable "elb_additional_security_group_ids" {
  type    = list(string)
  default = []
}

variable "instance_type" {
  default = "m5.large"
}

variable "instance_volume_type" {
  default = "standard"
}

variable "instance_volume_size" {
  default = "0"
}

variable "instance_volume_iops" {
  default = "0"
}

variable "rabbit_mgtport" {
  description = "RabbitMQ management port from outside ELB"
  default = "80"
}

variable "rabbit_port" {
  description = "RabbitMQ port from outside ELB"
  default = "5672"
}

variable "rabbit_username" {
  description = "Username for the rabbit account"
  default = "rabbit"
}

variable "enable_s3_logging" {
  description = "If true elb will store logs on S3"
  default = false
}

variable "internal_elb" {
  default = "true"
}

variable "tags" {
  type = map
}

