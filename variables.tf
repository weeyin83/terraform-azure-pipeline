##
# Common Variables
##
variable "tag_environment" {
  type    = string
  default = "Testing"
}

variable "tag_project" {
  type    = string
  default = "AzureCommunicationServices"
}

variable "tag_creator" {
  type    = string
  default = "TechieLass"
}

variable "location" {
  type    = string
  default = "Sweden Central"
}

##
# Domain Variables
##

variable "custom_domain" {
  description = "The custom domain for the email communication service"
  type        = string
  default     = "ctrlaltscots.com"
}