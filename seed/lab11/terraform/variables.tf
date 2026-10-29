variable "region" {
  description = "AWS region for the guestbook Lambda."
  type        = string
  default     = "@@AWS_REGION@@"
}

variable "participant" {
  description = "Unique id of the attendee; part of the Lambda function name and of the state key, so attendees don't collide."
  type        = string
}

variable "env_name" {
  description = "Environment name baked into the function name and reported by the Lambda (dev, staging, prod)."
  type        = string
}

variable "image_tag" {
  description = "Frontend image tag being promoted; surfaced as the Lambda VERSION env var."
  type        = string
  default     = "dev"
}

variable "function_prefix" {
  description = "Lambda function name prefix. MUST match the name pattern the AWS user is allowed to create."
  type        = string
  default     = "@@AWS_FUNCTION_PREFIX@@"
}

variable "execution_role_arn" {
  description = "ARN of the shared, pre-created Lambda execution role. The workshop credentials only need iam:PassRole on it."
  type        = string
  default     = "@@AWS_EXECUTION_ROLE_ARN@@"
}

variable "owner_email" {
  description = "Tag owner: who is responsible for what is created."
  type        = string
}

variable "cost_center" {
  description = "Tag cost_center."
  type        = string
  default     = "marketing"
}

variable "purpose" {
  description = "Tag purpose: the name of the workshop."
  type        = string
}
