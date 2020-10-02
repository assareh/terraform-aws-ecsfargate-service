output "alb_hostname" {
  value = aws_alb.main.dns_name
}

output "task_def" {
  value = aws_ecs_task_definition.main.arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}
