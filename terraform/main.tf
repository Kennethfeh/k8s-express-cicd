terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project   = var.cluster_name
      ManagedBy = "terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

# VPC for EKS
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id
  
  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Public subnets
resource "aws_subnet" "eks_public_subnets" {
  count = 2
  
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  map_public_ip_on_launch = true
  
  tags = {
    Name = "${var.cluster_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private subnets
resource "aws_subnet" "eks_private_subnets" {
  count = 2
  
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = {
    Name = "${var.cluster_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# NAT Gateways
resource "aws_eip" "eks_nat_eips" {
  count  = 2
  domain = "vpc"
  
  depends_on = [aws_internet_gateway.eks_igw]
  
  tags = {
    Name = "${var.cluster_name}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "eks_nat_gateways" {
  count = 2
  
  allocation_id = aws_eip.eks_nat_eips[count.index].id
  subnet_id     = aws_subnet.eks_public_subnets[count.index].id
  
  tags = {
    Name = "${var.cluster_name}-nat-gateway-${count.index + 1}"
  }
}

# Route tables
resource "aws_route_table" "eks_public_rt" {
  vpc_id = aws_vpc.eks_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }
  
  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table" "eks_private_rt" {
  count  = 2
  vpc_id = aws_vpc.eks_vpc.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat_gateways[count.index].id
  }
  
  tags = {
    Name = "${var.cluster_name}-private-rt-${count.index + 1}"
  }
}

# Route table associations
resource "aws_route_table_association" "eks_public_rta" {
  count = 2
  
  subnet_id      = aws_subnet.eks_public_subnets[count.index].id
  route_table_id = aws_route_table.eks_public_rt.id
}

resource "aws_route_table_association" "eks_private_rta" {
  count = 2
  
  subnet_id      = aws_subnet.eks_private_subnets[count.index].id
  route_table_id = aws_route_table.eks_private_rt[count.index].id
}
