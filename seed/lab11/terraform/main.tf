# A plain stateless Lambda with a public Function URL. It uses a shared, pre-created execution role
# (var.execution_role_arn), so the workshop credentials only manage Lambdas and never create IAM roles.
locals {
  name = "${var.function_prefix}-${var.participant}-${var.env_name}"
}

# Package the Lambda source as a Zip (no container image / ECR needed).
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "guestbook" {
  function_name    = local.name
  role             = var.execution_role_arn
  runtime          = "python3.12"
  handler          = "app.lambda_handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      STAGE   = var.env_name
      VERSION = var.image_tag
    }
  }
}

resource "aws_lambda_function_url" "guestbook" {
  function_name      = aws_lambda_function.guestbook.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }
}

# Required for an authorization_type = "NONE" Function URL to be publicly
# callable by the browser; without these the URL returns 403. This account
# requires BOTH lambda:InvokeFunctionUrl and lambda:InvokeFunction granted to
# all principals (per the Function URL console warning).
resource "aws_lambda_permission" "public_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.guestbook.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "public_invoke" {
  statement_id  = "AllowPublicInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guestbook.function_name
  principal     = "*"
  # NOTE: function_url_auth_type is only valid for the lambda:InvokeFunctionUrl
  # action, so it is intentionally omitted here.
}
