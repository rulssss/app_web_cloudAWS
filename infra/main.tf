provider "aws" {
  region = "us-east-2"
}

# Generar sufijo aleatorio para bucket único
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { 
    Name = "terraform-vpc-rulss"
    Project = "terraform-project"
  }
}


# Internet Gateway para conectividad
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { 
    Name = "terraform-igw-rulss"
    Project = "terraform-project"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true
  tags = { 
    Name = "terraform-subnet-main"
    Project = "terraform-project"
  }
}

# Segunda subnet OBLIGATORIA para RDS
resource "aws_subnet" "secondary" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-2b"
  tags = { 
    Name = "terraform-subnet-secondary"
    Project = "terraform-project"
  }
}

# Route Table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { 
    Name = "terraform-rt-main"
    Project = "terraform-project"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "ec2_sg" {
  name        = "terraform-ec2-sg-${random_string.bucket_suffix.result}"
  description = "Allow SSH and PostgreSQL from VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Flask Web (5000)"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-ec2-sg"
    Project = "terraform-project"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "terraform-rds-sg-${random_string.bucket_suffix.result}"
  description = "Allow Postgres access from EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "Postgres"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-rds-sg"
    Project = "terraform-project"
  }
}

resource "aws_instance" "web" {
  ami                    = "ami-0cfde0ea8edd312d4"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3 python3-pip git
    
    # Crear directorio para la app
    mkdir -p /home/ec2-user/app
    cd /home/ec2-user/app
    
    # Clonar el repositorio
    git clone https://github.com/rulssss/app_web_cloudAWS.git .
    
    # Instalar dependencias (si tienes requirements.txt)
    if [ -f requirements.txt ]; then
        pip3 install -r requirements.txt
    else
        pip3 install flask psycopg2-binary boto3
    fi
    
    # Crear archivo de variables de entorno
    cat > .env << EOL
DB_HOST=${aws_db_instance.db.address}
DB_NAME=${aws_db_instance.db.db_name}
DB_USER=${var.db_username}
DB_PASS=${var.db_password}
S3_BUCKET=${aws_s3_bucket.bucket.bucket}
EOL
    
    # Cambiar propietario de archivos
    chown -R ec2-user:ec2-user /home/ec2-user/app
    
    # Ejecutar la aplicación como ec2-user
    sudo -u ec2-user bash << 'EOSU'
    cd /home/ec2-user/app
    # Cargar variables de entorno
    export $(cat .env | xargs)
    # Ejecutar la app en background
    nohup python3 app.py > app.log 2>&1 &
EOSU
    
    # Crear servicio systemd para que se ejecute automáticamente
    cat > /etc/systemd/system/webapp.service << EOL
[Unit]
Description=Flask Web Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/app
EnvironmentFile=/home/ec2-user/app/.env
ExecStart=/usr/bin/python3 app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOL
    
    # Habilitar y arrancar el servicio
    systemctl enable webapp
    systemctl start webapp
  EOF
  
  tags = {
    Name = "terraform-web-server"
    Project = "terraform-project"
  }
}

# Usar AMBAS subnets para RDS (mínimo 2 zonas requerido por AWS)
resource "aws_db_subnet_group" "db_subnets" {
  name       = "terraform-db-subnet-group-${random_string.bucket_suffix.result}"
  subnet_ids = [aws_subnet.main.id, aws_subnet.secondary.id]
  tags = { 
    Name = "terraform-db-subnet-group"
    Project = "terraform-project"
  }
}

resource "aws_db_instance" "db" {
  identifier              = "terraform-mydb-rulss-${random_string.bucket_suffix.result}"
  allocated_storage       = 10
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = "db.t3.micro"
  username                = var.db_username
  password                = var.db_password
  skip_final_snapshot     = true
  db_subnet_group_name    = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]

  tags = {
    Name = "terraform-postgres-db"
    Project = "terraform-project"
  }
}

# Generar sufijo aleatorio para bucket único
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "bucket" {
  bucket = "rulssss-pryect-tf-${random_string.bucket_suffix.result}"

  tags = {
    Name = "terraform-s3-bucket"
    Project = "terraform-project"
  }
}

# Outputs 
output "db_host" {
  value = aws_db_instance.db.address
}

output "db_name" {
  value = aws_db_instance.db.db_name
}

output "db_user" {
  value = aws_db_instance.db.username
}

output "db_pass" {
  value = aws_db_instance.db.password
  sensitive = true
}

output "s3_bucket" {
  value = aws_s3_bucket.bucket.bucket
}

output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "app_url" {
  value = "http://${aws_instance.web.public_ip}:5000"
  description = "URL completa de tu aplicación Flask"
}