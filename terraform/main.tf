provider "aws" {
  region = "us-east-1"
}

# S3 for Frontend
resource "aws_s3_bucket" "frontend" {
  bucket = "my-ecart-frontend"
  acl    = "public-read"
}

# CloudFront CDN
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "S3Origin"
  }
  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3Origin"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }
}

# DynamoDB Table for Products
resource "aws_dynamodb_table" "products" {
  name         = "Products"
  billing_mode = "PAY_PER_REQUEST"
  attribute {
    name = "productId"
    type = "S"
  }
  hash_key = "productId"
}

# Lambda Function (Python 3.9)
resource "aws_lambda_function" "api" {
  function_name = "ecart-api"
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  s3_bucket     = aws_s3_bucket.frontend.bucket
  s3_key        = "lambda.zip"
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.products.name
    }
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "EcartAPI"
  description = "Simple e-cart API"
}

resource "aws_api_gateway_resource" "products" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "products"
}

resource "aws_api_gateway_method" "get_products" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.products.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id            = aws_api_gateway_rest_api.api.id
  resource_id            = aws_api_gateway_resource.products.id
  http_method            = aws_api_gateway_method.get_products.http_method
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.api.invoke_arn
}