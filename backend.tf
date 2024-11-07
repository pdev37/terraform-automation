terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-cs-0001"   # S3 버킷 이름
    key            = "s3-backend/terraform.tfstate"     # 상태 파일의 경로
    region         = "ap-northeast-2"                     # 버킷이 있는 리전
  }
}