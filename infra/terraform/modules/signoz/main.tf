locals {
  name_prefix = "${var.project_name}-${var.environment}"
  dns_name    = "signoz.${var.project_name}.internal"
}

data "aws_region" "current" {}

# Amazon Linux 2023, resolved once at create time (see ignore_changes below).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- Network -------------------------------------------------------------------------

resource "aws_security_group" "signoz" {
  name_prefix = "${local.name_prefix}-signoz-"
  description = "SigNoz collector - only reachable from the Django tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "OTLP/HTTP from the Django tasks"
    from_port       = 4318
    to_port         = 4318
    protocol        = "tcp"
    security_groups = [var.ecs_tasks_security_group_id]
  }

  # No inbound rule for the UI (8080): it is reached through an SSM port
  # forwarding session, so nothing about SigNoz is exposed outside the VPC.
  # Egress is HTTPS only: package repos, Docker Hub, GitHub releases and the
  # SSM agent's endpoints, all through the NAT Gateway.
  egress {
    description = "HTTPS via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-signoz"
  }
}

# Stable name for the collector, so the task definition never has to change
# when the instance (and its private IP) is replaced.
resource "aws_route53_zone" "internal" {
  name    = "${var.project_name}.internal"
  comment = "Private names for ${local.name_prefix}"

  vpc {
    vpc_id = var.vpc_id
  }
}

resource "aws_route53_record" "signoz" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = local.dns_name
  type    = "A"
  ttl     = 60
  records = [aws_instance.signoz.private_ip]
}

# --- Instance ----------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "signoz" {
  name               = "${local.name_prefix}-signoz"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Session Manager only: shell access and port forwarding without SSH keys or
# an inbound rule.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.signoz.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "signoz" {
  name = "${local.name_prefix}-signoz"
  role = aws_iam_role.signoz.name
}

resource "aws_instance" "signoz" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [aws_security_group.signoz.id]
  iam_instance_profile   = aws_iam_instance_profile.signoz.name

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    signoz_version    = var.signoz_version
    collector_version = var.collector_version
  })

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # ClickHouse data lives here (Docker volumes), so it survives reboots and
  # stop/start, but not a replacement of the instance.
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  lifecycle {
    # A new AL2023 release, or edits to the bootstrap script, must not
    # replace the instance (and wipe the stored traces) on a routine apply.
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name = "${local.name_prefix}-signoz"
  }
}

# Moves the instance to healthy hardware, keeping its EBS volume, private IP
# and therefore the data, if the underlying host fails.
resource "aws_cloudwatch_metric_alarm" "recover" {
  alarm_name          = "${local.name_prefix}-signoz-recover"
  alarm_description   = "Recover the SigNoz instance when the AWS system status check fails"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.name}:ec2:recover"]

  dimensions = {
    InstanceId = aws_instance.signoz.id
  }
}
