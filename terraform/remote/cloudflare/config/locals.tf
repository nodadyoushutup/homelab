locals {
  records_by_key = {
    for record in var.records : record.key => record
  }
}
