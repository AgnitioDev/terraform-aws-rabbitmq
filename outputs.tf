output "rabbitmq_elb_dns" {
  value = aws_elb.elb.dns_name
}

output "admin_password" {
  value     = random_string.admin_password.result
  sensitive = true
}

output "rabbit_password" {
  value     = random_string.rabbit_password.result
  sensitive = true
}

output "rabbit_username" {
  value = var.rabbit_username
}

output "secret_cookie" {
  value     = random_string.secret_cookie.result
  sensitive = true
}

output "elb_id" {
  value = aws_elb.elb.id
}

