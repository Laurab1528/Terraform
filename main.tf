provider "aws" {
  region = var.aws_region
}

# Crear el VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
}

# Crear el Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Crear la subred pública
resource "aws_subnet" "main" {
  count                  = 2
  vpc_id                 = aws_vpc.main.id
  cidr_block             = element(var.vpc_subnet_cidr, count.index)
  availability_zone      = element(var.aws_availability_zones, count.index)
  map_public_ip_on_launch = true
}

# Crear la tabla de rutas para la subred pública
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

# Asociar la tabla de rutas con la subred pública
resource "aws_route_table_association" "public" {
  count            = 2
  subnet_id        = aws_subnet.main[count.index].id
  route_table_id   = aws_route_table.public.id
}


# Crear el grupo de seguridad para el ALB
resource "aws_security_group" "elb_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Crear el grupo de seguridad para las instancias EC2
resource "aws_security_group" "ec2_sg" {
  name        = "my-security-group"
  description = "Security group for EC2 instances"
  vpc_id      = "vpc-12345678"  # Asegúrate de que este ID sea correcto

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Crear las instancias EC2
resource "aws_instance" "web" {
  count         = 2
  ami           = var.instance_ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main[count.index].id
  security_groups = [aws_security_group.ec2_sg.name]


}


# Crear el Application Load Balancer
resource "aws_lb" "web_lb" {
  name               = "unique-web-lb-name"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_sg.id]
  subnets            = aws_subnet.public.*.id
  enable_deletion_protection = false

  enable_cross_zone_load_balancing = true
  enable_http2                       = true
}




# Crear el listener para el ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Success"
      status_code  = "200"
    }
  }
}

# Crear el grupo de destino para el ALB
resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    path                = "/"
  }
}

# Asociar las instancias EC2 al grupo de destino del ALB
resource "aws_lb_target_group_attachment" "web_instance" {
  count             = 2
  target_group_arn  = aws_lb_target_group.web_tg.arn
  target_id         = aws_instance.web[count.index].id
  port              = 80
}
