output "lambda_url" {
  description = "Public Function URL of the guestbook Lambda."
  value       = aws_lambda_function_url.guestbook.function_url
}
