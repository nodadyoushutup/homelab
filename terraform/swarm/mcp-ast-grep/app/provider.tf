terraform {
  backend "s3" {
    key = "mcp-ast-grep.tfstate"
  }
}
