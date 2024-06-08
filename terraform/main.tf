module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = var.vpc_cidr

  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = var.private_subnets

  tags = {
    Owner     = "YourName"
    CreatedBy = "YourName"
    Purpose   = "Test VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name    = "my-igw"
    Owner   = "YourName"
    Purpose = "Internet Gateway"
  }
}

resource "aws_route_table" "public" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name    = "public-route-table"
    Owner   = "YourName"
    Purpose = "Public Route Table"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(module.vpc.public_subnets)
  subnet_id      = module.vpc.public_subnets[count.index]
  route_table_id = aws_route_table.public.id
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "app" {
  count         = var.instance_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  key_name = aws_key_pair.deployer.key_name

  subnet_id = element(module.vpc.private_subnets, count.index)

  tags = {
    Name    = "docker-instance-${count.index}"
    Owner   = "YourName"
    Purpose = "Docker Server"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io",
      "sudo usermod -aG docker ubuntu",
      "sudo apt-add-repository --yes --update ppa:ansible/ansible",
      "sudo apt-get install -y ansible"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.private_ip
    }
  }

  provisioner "file" {
    source      = "~/.ssh/id_rsa.pub"
    destination = "/home/ubuntu/.ssh/authorized_keys"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.private_ip
    }
  }
}

resource "aws_eip" "app" {
  count = var.instance_count

  instance = aws_instance.app[count.index].id
}

resource "aws_lb" "example" {
  name               = "example"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = [module.vpc.default_security_group_id]

  tags = {
    Owner   = "YourName"
    Purpose = "Test Load Balancer"
  }
}

resource "aws_lb_listener" "grafana" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_lb_target_group" "grafana" {
  name        = "grafana"
  port        = 3000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Owner   = "YourName"
    Purpose = "Grafana Target Group"
  }
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana.arn
  count            = 1

  target_id = aws_instance.app[count.index % length(aws_instance.app)].id
}

// Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  filename = "ansible_inventory.ini"
  content = templatefile("${path.module}/ansible_inventory.tpl", {
    instance_private_ips = aws_instance.app[*].private_ip
  })
}

