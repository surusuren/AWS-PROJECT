# Creating a VPC

resource "aws_vpc" "project-vpc" {
    cidr_block           = var.vpc-cidr
    enable_dns_support   = true
    enable_dns_hostnames = true
    tags = {
        Name = "project-vpc"
  }
}

# Internet Gateway for VPC

resource "aws_internet_gateway" "project-igw" {
    vpc_id = aws_vpc.project-vpc.id
}

# Create Public & Private Route Tables for VPC

resource "aws_route_table" "public-route-table" {
    vpc_id = aws_vpc.project-vpc.id
}

# Route the public subnet traffic through the Internet Gateway

resource "aws_route" "public-internet-igw-route" {
    route_table_id         = aws_route_table.public-route-table.id
    gateway_id             = aws_internet_gateway.project-igw.id
    destination_cidr_block = "0.0.0.0/0"
}

# Public subnets

resource "aws_subnet" "public-subnet-1" {
    cidr_block              = var.public_subnet_1_cidr
    vpc_id                  = aws_vpc.project-vpc.id
    availability_zone       = var.availability_zones[0]
    map_public_ip_on_launch = true
}

resource "aws_subnet" "public-subnet-2" {
    cidr_block              = var.public_subnet_2_cidr
    vpc_id                  = aws_vpc.project-vpc.id
    availability_zone       = var.availability_zones[1]
    map_public_ip_on_launch = true
}

# Private subnets

resource "aws_subnet" "private-subnet-1" {
    cidr_block        = var.private_subnet_1_cidr
    vpc_id            = aws_vpc.project-vpc.id
    availability_zone = var.availability_zones[0]
}
resource "aws_subnet" "private-subnet-2" {
    cidr_block        = var.private_subnet_2_cidr
    vpc_id            = aws_vpc.project-vpc.id
    availability_zone = var.availability_zones[1]
}

# Associate the newly created route tables to the subnets

resource "aws_route_table_association" "public-route-1-association" {
    route_table_id = aws_route_table.public-route-table.id
    subnet_id      = aws_subnet.public-subnet-1.id
}

resource "aws_route_table_association" "public-route-2-association" {
    route_table_id = aws_route_table.public-route-table.id
    subnet_id      = aws_subnet.public-subnet-2.id
}

# Elastic IP

resource "aws_eip" "elastic-ip-for-nat-gateway" {
    vpc                       = true
    associate_with_private_ip = "10.10.0.5"
    depends_on                = [aws_internet_gateway.project-igw]
}

# Implementing NAT Gateways for communication with outside world

resource "aws_nat_gateway" "nat-gateway" {
    depends_on      = [aws_eip.elastic-ip-for-nat-gateway]
    allocation_id   = aws_eip.elastic-ip-for-nat-gateway.id
    subnet_id       = aws_subnet.public-subnet-1.id
}

resource "aws_route_table" "private-route-table" {
    vpc_id = aws_vpc.project-vpc.id
}

# Route the private subnet traffic through the NAT Gateway

resource "aws_route" "private-nat-gateway-route" {
    route_table_id         = aws_route_table.private-route-table.id
    nat_gateway_id         = aws_nat_gateway.nat-gateway.id
    destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private-route-1-association" {
    route_table_id = aws_route_table.private-route-table.id
    subnet_id      = aws_subnet.private-subnet-1.id
}

resource "aws_route_table_association" "private-route-2-association" {
    route_table_id = aws_route_table.private-route-table.id
    subnet_id      = aws_subnet.private-subnet-2.id
}

# Implementing Security Groups

resource "aws_security_group" "alb" {
    name    = "lb-security-group"
    vpc_id  = aws_vpc.project-vpc.id

    ingress {
        protocol    = "tcp"
        from_port   = 80
        to_port     = 80
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        protocol    = "tcp"
        from_port   = 443
        to_port     = 443
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        protocol    = "tcp"
        from_port   = 3000
        to_port     = 3000
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# Implementing Security Group for ECS
# Remove ports 80 and 443 later (Used it for testing)
resource "aws_security_group" "ecs-tasks" {
    name    = "ecs-security-group"
    vpc_id  = aws_vpc.project-vpc.id

    ingress {
        protocol    = "tcp"
        from_port   = var.container_port
        to_port     = var.container_port
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        protocol    = "tcp"
        from_port   = 80
        to_port     = 80
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        protocol    = "tcp"
        from_port   = 443
        to_port     = 443
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        protocol    = "tcp"
        from_port   = 3000
        to_port     = 3000
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
    }
}
resource "aws_security_group_rule" "opened_to_alb" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 0
  to_port                  = 0
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = "${aws_security_group.ecs-tasks.id}"
}
/* # Implementing ECR (Elastic Container Registry)

resource "aws_ecr_repository" "project_ecr_repo" {
    name                    = "project-repo"
    image_tag_mutability    = "MUTABLE"
}
 */
/* # Lifecycle Policy for ECR Docker images (Max 5 images)

resource "aws_ecr_lifecycle_policy" "ecr_lifecycle_policy" {
    repository = aws_ecr_repository.project_ecr_repo.name

    policy = jsonencode({
        rules = [{
            rulePriority = 1
            description = "Keep last 5 images"
            action = {
                type = "expire"
            }
            selection = {
                tagStatus = "any"
                countType = "imageCountMoreThan"
                countNumber = 5
            }
        }]
    })
}
 */
# Creating a cluster for ECS

resource "aws_ecs_cluster" "project-cluster" {
    name = "project-cluster"
}

# Creating a task definition for ECS

variable "docker_image_URL" {
    description = "DOcker Image URL from the ECR"
    default = "394820470736.dkr.ecr.us-east-1.amazonaws.com/urls:latest"
}

variable "database_image_URL" {
    description = "Docker Image URL from the ECR for database"
    default = "394820470736.dkr.ecr.us-east-1.amazonaws.com/db:latest"
}

# For application container
resource "aws_ecs_task_definition" "project-task" {
    family                   = "project-task"
    container_definitions    = <<DEFINITION
    [
        {
        "name": "urls",
        "image": "${var.docker_image_URL}",
        "essential": true,
        "portMappings": [
            {
            "protocol": "tcp",
            "containerPort": 3000
            }
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "ecsTaskExecutionRole",  
                "awslogs-region": "us-east-1",
                "awslogs-stream-prefix": "streaming"
            }
        }
        },
        {
        "name": "db",
        "image": "${var.database_image_URL}",
        "essential": true,
        "portMappings": [
            {
            "protocol": "tcp",
            "containerPort": 27017
            }
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "ecsTaskExecutionRole",  
                "awslogs-region": "us-east-1",
                "awslogs-stream-prefix": "streaming"
            }
        }

        }
    ]
    DEFINITION
    requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
    network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
    memory                   = 3072         # Specifying the memory our container requires
    cpu                      = 1024          # Specifying the CPU our container requires
    execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
    task_role_arn            = aws_iam_role.ecsTaskExecutionRole.arn
}

# For database container
/*
resource "aws_ecs_task_definition" "project-task1" {
    family                   = "project-task1"
    container_definitions    = <<DEFINITION
    [
        {
        "name": "db",
        "image": "${var.database_image_URL}",
        "essential": true,
        "portMappings": [
            {
            "protocol": "tcp",
            "containerPort": 27017
            }
        ]
        }
    ]
    DEFINITION
    requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
    network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
    memory                   = 1024         # Specifying the memory our container requires
    cpu                      = 256         # Specifying the CPU our container requires
    execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
    task_role_arn            = aws_iam_role.ecsTaskExecutionRole.arn
}
*/
# Creating IAM role for ECS Tasks

resource "aws_iam_role" "ecsTaskRole" {
    name = "ecs-Task-Role"

    assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                    "Service": "ecs-tasks.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
}

resource "aws_iam_policy" "dynamodb" {
    name        = "task-policy-dynamodb"
    description = "Policy that allows access to DynamoDB"

    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:UpdateTimeToLive",
                "dynamodb:PutItem",
                "dynamodb:DescribeTable",
                "dynamodb:ListTables",
                "dynamodb:DeleteItem",
                "dynamodb:GetItem",
                "dynamodb:Scan",
                "dynamodb:Query",
                "dynamodb:UpdateItem",
                "dynamodb:UpdateTable"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-policy-attachment" {
    role        = aws_iam_role.ecsTaskRole.name
    policy_arn  = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

# Another role is needed to execute the tasks "serverlessly" with Fargate Config

resource "aws_iam_role" "ecsTaskExecutionRole" {
    name               = "ecs-Task-Execution-Role"
    assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                    "Service": "ecs-tasks.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
    role       = aws_iam_role.ecsTaskExecutionRole.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# Implementing Load Balancer

resource "aws_lb" "load-balancer" {
    name                        = "load-balancer"
    internal                    = false
    load_balancer_type          = "application"
    security_groups             = [aws_security_group.alb.id]
    subnets                     = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id]
    enable_deletion_protection  = false
}

resource "aws_alb_target_group" "lb-target-group" {
    name            = "lb-target-group"
    port            = 3000
    protocol        = "HTTP"
    vpc_id          = aws_vpc.project-vpc.id
    target_type     = "ip"
    depends_on      = [
        aws_lb.load-balancer
    ]
    health_check {
        healthy_threshold   = "3"
        interval            = "30"
        protocol            = "HTTP"
        matcher             = "200"
        timeout             = "3"
        path                = var.health_check_path
        unhealthy_threshold = "2"
    }
}

resource "aws_alb_listener" "http" {
    load_balancer_arn   = aws_lb.load-balancer.id
    port                = 80
    protocol            = "HTTP"
    depends_on          = [aws_alb_target_group.lb-target-group]
    default_action {
        type = "forward"
         target_group_arn = aws_alb_target_group.lb-target-group.arn
    }
}

resource "aws_alb_listener" "https" {
    load_balancer_arn   = aws_lb.load-balancer.id
    port                = 443
    protocol            = "HTTPS"
    depends_on          = [aws_alb_target_group.lb-target-group]
    ssl_policy          = "ELBSecurityPolicy-2016-08"
    certificate_arn     = var.alb_tls_cert_arn

    default_action {
        target_group_arn    = aws_alb_target_group.lb-target-group.arn
        type                = "forward"
    }
}


# Creating an ECS Service to run this task

resource "aws_ecs_service" "project-service" {
    name                                = "project-service"                          # Naming our first service
    cluster                             = aws_ecs_cluster.project-cluster.id         # Referencing our created Cluster
    task_definition                     = aws_ecs_task_definition.project-task.arn   # Referencing the task our service will spin up
    launch_type                         = "FARGATE"
    desired_count                       = 2                                          # Setting the number of containers we want deployed to 2
    scheduling_strategy                 = "REPLICA"
    deployment_minimum_healthy_percent  = 50
    deployment_maximum_percent          = 200

    network_configuration {
    subnets             = ["${aws_subnet.public-subnet-1.id}", "${aws_subnet.public-subnet-2.id}"]
    assign_public_ip    = true
    security_groups     = [aws_security_group.ecs-tasks.id]
    }
    
    load_balancer {
        target_group_arn    = aws_alb_target_group.lb-target-group.arn
        container_name      = "urls"
        container_port      = var.container_port
    }
    
    lifecycle {
        ignore_changes = [task_definition, desired_count]
    }
}

# Creating an ECS Service to run Database task
/*
resource "aws_ecs_service" "project-service1" {
    name                                = "project-service1"                          # Naming our first service
    cluster                             = aws_ecs_cluster.project-cluster.id         # Referencing our created Cluster
    task_definition                     = aws_ecs_task_definition.project-task1.arn   # Referencing the task our service will spin up
    launch_type                         = "FARGATE"
    desired_count                       = 2                                          # Setting the number of containers we want deployed to 2
    scheduling_strategy                 = "REPLICA"
    deployment_minimum_healthy_percent  = 50
    deployment_maximum_percent          = 200

    network_configuration {
    subnets             = ["${aws_subnet.private-subnet-1.id}", "${aws_subnet.private-subnet-2.id}"]
    assign_public_ip    = true
    security_groups     = [aws_security_group.ecs-tasks.id]
    }

    load_balancer {
        target_group_arn    = aws_alb_target_group.lb-target-group.arn
        container_name      = "project-repo1"
        container_port      = var.container_port
    }

    lifecycle {
        ignore_changes = [task_definition, desired_count]
    }
}
*/
# Implementing AutoScaling

resource "aws_appautoscaling_target" "ecs_target" {
    max_capacity        = 4
    min_capacity        = 2
    resource_id         = "service/${aws_ecs_cluster.project-cluster.name}/${aws_ecs_service.project-service.name}"
    scalable_dimension  = "ecs:service:DesiredCount"
    service_namespace   = "ecs"
}

resource "aws_appautoscaling_policy" "ecs-policy-cpu" {
    name                = "cpu-autoscaling"
    policy_type         = "TargetTrackingScaling"
    resource_id         = aws_appautoscaling_target.ecs_target.resource_id
    scalable_dimension  = aws_appautoscaling_target.ecs_target.scalable_dimension
    service_namespace   = aws_appautoscaling_target.ecs_target.service_namespace

    target_tracking_scaling_policy_configuration {
        predefined_metric_specification {
            predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
        target_value = 60
    }
} 
