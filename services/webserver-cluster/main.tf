data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    # Replace this with your bucket name!
    bucket = "tfstate-remote-sai"
    key    = "stage/data-stores/mysql/terraform.tfstate"
    region = "ap-southeast-1"
  }
}
resource "aws_instance" "webserver" {
  ami           = "ami-0d058fe428540cd89"
  instance_type = "var.instance_type"
  vpc_security_group_ids = [aws_security_group.webserver-sg.id]
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p "{var.server_port}" &
              EOF
  tags = {
    Name = "terraform-firstinstance"
  }
}

resource "aws_security_group" "webserver-sg" {
  name = "${var.cluster_name}-instance"
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 8080
}
output "public_ip" {
  value       = aws_instance.webserver.public_ip
  description = "The public IP of the web server"
}

resource "aws_launch_configuration" "launch-config" {
  image_id        = "ami-0d6ba217f554f6137"
  instance_type   = "var.instance_type"
  security_groups = [aws_security_group.webserver-sg.id]

user_data = <<EOF
#!/bin/bash
db_address="${data.terraform_remote_state.db.outputs.address}"
db_port="${data.terraform_remote_state.db.outputs.port}"
echo "Hello, World. DB is at $db_address:$db_port" >> index.html
nohup busybox httpd -f -p "${var.server_port}" &
EOF
  lifecycle {
    create_before_destroy = true
  }
    
}

data "aws_availability_zones" "all" {
    }
    
resource "aws_autoscaling_group" "auto-asg" {
  launch_configuration = aws_launch_configuration.launch-config.id
  availability_zones   = data.aws_availability_zones.all.names
  min_size = var.min_size
  max_size = var.max_size
  
  load_balancers    = [aws_elb.example.name]
  health_check_type = "ELB"
  
  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-autosg"
    propagate_at_launch = true
  }
}

# Create Load Balancer
resource "aws_elb" "example" {
  name               = "${var.cluster_name}-elb"
  availability_zones = data.aws_availability_zones.all.names
  security_groups    = [aws_security_group.elb-sg.id]
  
  health_check {
    target              = "HTTP:${var.server_port}/"
    interval            = 30
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
    # This adds a listener for incoming HTTP requests.
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = var.server_port
    instance_protocol = "http"
}
}

resource "aws_security_group" "elb-sg" {
  name = "${var.cluster_name}-elb"
  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Inbound HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
output "clb_dns_name" {
  value       = aws_elb.example.dns_name
  description = "The domain name of the load balancer"
}

