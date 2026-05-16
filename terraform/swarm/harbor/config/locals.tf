locals {
  # Always manage a single core project `homelab` for all homelab images
  # (`registry/homelab/<repo>:<tag>`). Entries in var.projects with the same name
  # override these defaults; additional project names extend the map.
  default_homelab_project = {
    name                   = "homelab"
    public                 = false
    vulnerability_scanning = true
  }

  project_specs = merge(
    { homelab = local.default_homelab_project },
    { for project in var.projects : project.name => project },
  )

  user_specs = {
    for user in var.users :
    user.username => user
  }

  project_member_specs = {
    for member in var.project_members :
    "${member.project_name}:${member.user_name}" => member
  }

  robot_account_specs = {
    for robot in var.robot_accounts :
    robot.name => robot
  }
}
