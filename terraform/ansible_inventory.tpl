# Ansible inventory file

[app_servers]
%{ for ip in instance_private_ips ~}
app${ip} ansible_host=${ip}
%{ endfor ~}
