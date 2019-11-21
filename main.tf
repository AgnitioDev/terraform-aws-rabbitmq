locals {
  sync_node_count = 3
  rabbit_internal_port = 5672
  log_bucket_name = "${var.name}-log-${random_uuid.log.result}"
}

data "aws_region" "current" {
}

data "aws_ami_ids" "ami" {
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-2017*-gp2"]
  }
}

resource "random_uuid" "log" { }

resource "random_string" "admin_password" {
  length  = 32
  special = false
}

resource "random_string" "rabbit_password" {
  length  = 32
  special = false
}

resource "random_string" "secret_cookie" {
  length  = 64
  special = false
}

data "aws_iam_policy_document" "policy_doc" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "template_file" "cloud-init" {
  template = file("${path.module}/cloud-init.yaml")

  vars = {
    sync_node_count = local.sync_node_count
    asg_name        = var.name
    region          = data.aws_region.current.name
    admin_password  = random_string.admin_password.result
    rabbit_password = random_string.rabbit_password.result
    secret_cookie   = random_string.secret_cookie.result
    message_timeout = 3 * 24 * 60 * 60 * 1000 # 3 days
  }
}

resource "aws_iam_role" "role" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.policy_doc.json
}

resource "aws_iam_role_policy" "policy" {
  name = var.name
  role = aws_iam_role.role.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingInstances",
                "ec2:DescribeInstances"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF

}

resource "aws_iam_instance_profile" "profile" {
  name_prefix = var.name
  role        = aws_iam_role.role.name
}

resource "aws_security_group" "rabbitmq_elb" {
  name = "${var.name}-sg-elb"
  vpc_id = var.vpc_id
  description = "Security Group for the rabbitmq elb"

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-elb"
  })
}

resource "aws_security_group" "rabbitmq_nodes" {
  name = "${var.name}-sg-nodes"
  vpc_id = var.vpc_id
  description = "Security Group for the rabbitmq nodes"

  ingress {
    protocol = -1
    from_port = 0
    to_port = 0
    self = true
  }

  ingress {
    protocol = "tcp"
    from_port = 5672
    to_port = 5672
    security_groups = [
      aws_security_group.rabbitmq_elb.id]
  }

  ingress {
    protocol = "tcp"
    from_port = 15672
    to_port = 15672
    security_groups = [
      aws_security_group.rabbitmq_elb.id]
  }

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  tags = merge(var.tags, {
    "Name" = "${var.name}-sg-nodes"
  })
}

resource "aws_launch_configuration" "rabbitmq" {
  name                 = "${var.name}-launch-configuration"
  image_id             = data.aws_ami_ids.ami.ids[0]
  instance_type        = var.instance_type
  key_name             = var.ssh_key_name
  security_groups      = concat([aws_security_group.rabbitmq_nodes.id], var.nodes_additional_security_group_ids)
  iam_instance_profile = aws_iam_instance_profile.profile.id
  user_data            = data.template_file.cloud-init.rendered

  root_block_device {
    volume_type           = var.instance_volume_type
    volume_size           = var.instance_volume_size
    iops                  = var.instance_volume_iops
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "rabbitmq" {
  name = "${var.name}-asg"
  min_size = var.min_size
  desired_capacity = var.desired_size
  max_size = var.max_size
  health_check_grace_period = 300
  health_check_type = "ELB"
  force_delete = true
  launch_configuration = aws_launch_configuration.rabbitmq.name
  load_balancers = [
    aws_elb.elb.name]
  vpc_zone_identifier = var.subnet_ids

  tag {
    key = "Name",
    value = "${var.name}-asg",
    propagate_at_launch = true
  }
}

resource "aws_elb" "elb" {
  name = "${var.name}-elb"

  access_logs {
    bucket = local.log_bucket_name
    bucket_prefix = "elb"
    interval = 60
    enabled = var.enable_s3_logs
  }

  listener {
    instance_port = local.rabbit_internal_port
    instance_protocol = "tcp"
    lb_port = var.rabbit_port
    lb_protocol = "tcp"
  }

  /*listener {
    instance_port      = 8000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/certName"
  }*/

  listener {
    instance_port = 15672
    instance_protocol = "http"
    lb_port = var.rabbit_mgtport
    lb_protocol = "http"
  }

  health_check {
    interval = 30
    unhealthy_threshold = 10
    healthy_threshold = 2
    timeout = 3
    target = "TCP:${local.rabbit_internal_port}"
  }

  subnets = var.subnet_ids
  idle_timeout = 3600
  internal = var.internal_elb
  security_groups = concat([
    aws_security_group.rabbitmq_elb.id], var.elb_additional_security_group_ids)

  #cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name = "${var.name}-elb"
  })
}

data "aws_elb_service_account" "default" {
}

data "aws_iam_policy_document" "logs_policy_doc" {
  statement {
    sid       = "Allow ALB to write logs"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.log_bucket_name}/*"]
    principals {
      type        = "AWS"
      identifiers = [join("", data.aws_elb_service_account.default.*.arn)]
    }
  }
}

module "log" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 1.0"

  create_bucket = var.enable_s3_logs
  bucket = local.log_bucket_name
  acl = "private"
  force_destroy = true

  lifecycle_rule = [
    {
      id = "log"
      enabled = true
      prefix = "log/"

      tags = {
        rule = "log"
        autoclean = "true"
      }

      transition = [
        {
          days = 90
          storage_class = "ONEZONE_IA"
        },
        {
          days = 120
          storage_class = "GLACIER"
        }
      ]

      expiration = {
        days = 730
        # 2 YEARS
      }
    },
  ]

  policy = data.aws_iam_policy_document.logs_policy_doc.json

  tags = var.tags
}