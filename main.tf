provider "aws" {
  region = var.region
}

### Network

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = "10.10.0.0/16"
  tags       = local.common_tags
}

resource "aws_subnet" "main" {
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.main.id
  tags              = local.common_tags
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = local.common_tags
}

resource "aws_route_table" "r" {
  vpc_id = aws_vpc.main.id
  tags   = local.common_tags

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  count          = var.az_count
  subnet_id      = element(aws_subnet.main.*.id, count.index)
  route_table_id = aws_route_table.r.id
}

### Security

resource "aws_security_group" "lb_sg" {
  description = "controls access to the application ELB"

  vpc_id = aws_vpc.main.id
  name   = "${var.region}-${var.environment}-${var.app_name}-ecs-lbsg"
  tags   = local.common_tags

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "aws_security_group" "instance_sg" {
  description = "controls direct access to application instances"
  vpc_id      = aws_vpc.main.id
  name        = "${var.region}-${var.environment}-${var.app_name}-ecs-inst-sg"
  tags        = local.common_tags

  ingress {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80

    security_groups = [
      aws_security_group.lb_sg.id,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## ECS

resource "aws_ecs_cluster" "main" {
  name = "${var.region}-${var.environment}-${var.app_name}-ecs-cluster"
  tags = local.common_tags
}

resource "aws_ecs_service" "main" {
  name            = "${var.region}-${var.environment}-${var.app_name}-ecs-lbsg"
  cluster         = aws_ecs_cluster.main.id
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.service_desired
  tags            = local.common_tags

  load_balancer {
    target_group_arn = aws_alb_target_group.test.id
    container_name   = var.app_name
    container_port   = "80"
  }

  network_configuration {
    security_groups  = [aws_security_group.instance_sg.id]
    subnets          = [aws_subnet.main[0].id, aws_subnet.main[1].id]
    assign_public_ip = true
  }

  depends_on = [
    aws_alb_listener.front_end,
  ]
}

data "template_file" "task_definition" {
  template = file("${path.module}/task-definition.json")

  vars = {
    image_url        = var.docker_image
    container_name   = var.app_name
    log_group_region = var.region
    log_group_name   = aws_cloudwatch_log_group.app.name
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.region}-${var.environment}-${var.app_name}"
  container_definitions    = data.template_file.task_definition.rendered
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.task_init.arn
  cpu                      = 1024
  memory                   = 2048
  tags                     = local.common_tags
}

## IAM

resource "aws_iam_role" "task_init" {
  name               = "${var.region}-${var.environment}-${var.app_name}-task-init-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_definition.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "assume_role_policy_definition" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role_policy_attachment" "task_init_policy" {
  role       = aws_iam_role.task_init.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_init_policy" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "task_init_policy" {
  role   = aws_iam_role.task_init.name
  name   = "AllowlogsCreateLogGroup"
  policy = data.aws_iam_policy_document.task_init_policy.json
}

## ALB

resource "aws_alb" "main" {
  name            = "${var.region}-${var.environment}-${var.app_name}-alb"
  subnets         = aws_subnet.main.*.id
  security_groups = [aws_security_group.lb_sg.id]
  tags            = local.common_tags
}

resource "aws_alb_target_group" "test" {
  name        = "${var.region}-${var.environment}-${var.app_name}-tgt-grp"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
  tags        = local.common_tags
}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.test.id
    type             = "forward"
  }
}

## CloudWatch Logs

resource "aws_cloudwatch_log_group" "ecs" {
  name = "${var.region}-${var.environment}-${var.app_name}/ecs"
  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "app" {
  name = "${var.region}-${var.environment}-${var.app_name}/app"
  tags = local.common_tags
}
