# IAM Role for EC2 — allows S3, Lex, and SSM access without hardcoded credentials
resource "aws_iam_role" "app_ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "app_permissions" {
  name = "${var.project_name}-app-policy"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.uploads.arn,
          "${aws_s3_bucket.uploads.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["lex:RecognizeText", "lex:RecognizeUtterance", "lex:DeleteSession", "lex:GetSession"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.app_ec2.name
}

# Application Load Balancer
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/up"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = "ami-0c802847a7dd848c0" # Amazon Linux 2023 ap-southeast-1
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  # Allow Docker containers inside EC2 to reach IMDS (IAM role credentials)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Install Docker and Git
    yum update -y
    yum install -y docker git

    # Install Docker Compose v2 plugin
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # Start Docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # Clone application repository
    git clone ${var.github_repo_url} /opt/kaltim-app
    cd /opt/kaltim-app

    # Write docker .env (uses RDS + ElastiCache + S3 + Lex)
    cat > docker/.env << 'ENVEOF'
    APP_KEY=${var.app_key}
    JWT_SECRET=${var.jwt_secret}
    DB_DATABASE=${var.db_name}
    DB_USERNAME=${var.db_username}
    DB_PASSWORD=${var.db_password}
    DB_ROOT_PASSWORD=${var.db_password}
    DB_HOST=${aws_db_instance.main.address}
    DB_PORT=3306
    REDIS_HOST=${aws_elasticache_cluster.main.cache_nodes[0].address}
    REDIS_PORT=6379
    APP_PORT=80
    APP_URL=http://${aws_lb.app.dns_name}
    AWS_DEFAULT_REGION=${var.aws_region}
    AWS_BUCKET=${aws_s3_bucket.uploads.bucket}
    AWS_LEX_BOT_ID=${aws_lexv2models_bot.kaltim.id}
    AWS_LEX_BOT_ALIAS_ID=${aws_lexv2models_bot_alias.prod.bot_alias_id}
    CACHE_STORE=redis
    SESSION_DRIVER=redis
    FILESYSTEM_DISK=s3
    ENVEOF

    # Start application
    docker compose -f docker/docker-compose.yml up -d --build
  EOF
  )

  tags = {
    Name        = "${var.project_name}-launch-template"
    Environment = var.environment
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = aws_subnet.app_private[*].id
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}
