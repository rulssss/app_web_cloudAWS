provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "web" {
  ami           = "ami-076838d6a293cb49e" # Ubuntu 22.04 en us-east-1
  instance_type = "t2.micro"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "rulssss-pryect-tf"
  acl    = "private"
}

resource "aws_db_instance" "db" {
  identifier        = "mydb-rulss"
  allocated_storage = 10
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  username          = var.db_username
  password          = var.db_password
  skip_final_snapshot = true
}
