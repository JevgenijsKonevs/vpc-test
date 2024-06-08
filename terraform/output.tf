output "instance_ips" {
  value = aws_instance.app.*.public_ip
}
