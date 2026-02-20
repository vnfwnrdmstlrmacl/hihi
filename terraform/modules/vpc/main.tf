# 현재 리전에서 사용 가능한 가용 영역 목록 가져오기
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC 생성
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway (Public Subnet 통신용)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Subnets (Tailscale Bridge 등이 위치)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index) # 10.0.0.0/24, 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-net-${count.index}"
  }
}

# Private Subnets (RDS, DMS 가 위치)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # 10.0.10.0/24, 10.0.11.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-net-${count.index}"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Public Subnet Route Table 연결
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 1. Private Route Table 생성
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # [핵심] 온프레미스(Tailscale) IP 대역에 대한 경로를 Bridge 인스턴스로 지정
  # var.onprem_cidr은 보통 100.64.0.0/10 (Tailscale 기본) 혹은 실제 온프레 대역

  tags = { Name = "${var.project_name}-private-rt" }
}

# 2. Private Subnet 연결
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
# (참고) Private Subnet용 NAT Gateway는 비용 절감을 위해 생략했습니다. 
# 만약 Private 자원이 외부 패키지 업데이트 등이 필요하다면 추가가 필요합니다.
