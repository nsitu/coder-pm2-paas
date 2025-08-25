terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

# Setup Variables
# username is a shorthand for the owner.
# ixd_domain (is probably ixdcoder.com or sheridanixd.com)
# workspace_slug - 8 pseudo random characters derived from the id of the workspace
# this is used as part of the editor URL and makes it  difficult guess 
# note you could make this longer but  a subdomain string cannot be longer than 63 characters 
# so it is good to leave some space for the actual name of the project.

locals {
  username = data.coder_workspace_owner.me.name
  ixd_domain = "ixdcoder.com"
  workspace_slug = substr(md5(data.coder_workspace.me.id), 0, 8)
}

provider "coder" {
}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces). If the Coder host is itself running as a Pod on the same Kubernetes cluster as you are deploying workspaces to, set this to the same namespace."
}
 
  
data "coder_parameter" "slot_a_subdomain" {
  name         = "SLOT_A_SUBDOMAIN"
  display_name = "Slot A Subdomain"
  description  = "Subdomain for slot A (alphanumeric, dashes, max 63 chars)"
  type         = "string"
  mutable      = true
  default      = "a"
  validation {
    regex = "^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$"
    error = "Slot A subdomain must contain only alphanumeric characters and dashes, start and end with alphanumeric characters, and be 1-63 characters long."
  }
}

data "coder_parameter" "slot_b_subdomain" {
  name         = "SLOT_B_SUBDOMAIN"
  display_name = "Slot B Subdomain"
  description  = "Subdomain for slot B (alphanumeric, dashes, max 63 chars)"
  type         = "string"
  mutable      = true
  default      = "b"
  validation {
    regex = "^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$"
    error = "Slot B subdomain must contain only alphanumeric characters and dashes, start and end with alphanumeric characters, and be 1-63 characters long."
  }
}

data "coder_parameter" "slot_c_subdomain" {
  name         = "SLOT_C_SUBDOMAIN"
  display_name = "Slot C Subdomain"
  description  = "Subdomain for slot C (alphanumeric, dashes, max 63 chars)"
  type         = "string"
  mutable      = true
  default      = "c"
  validation {
    regex = "^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$"
    error = "Slot C subdomain must contain only alphanumeric characters and dashes, start and end with alphanumeric characters, and be 1-63 characters long."
  }
}

data "coder_parameter" "slot_d_subdomain" {
  name         = "SLOT_D_SUBDOMAIN"
  display_name = "Slot D Subdomain"
  description  = "Subdomain for slot D (alphanumeric, dashes, max 63 chars)"
  type         = "string"
  mutable      = true
  default      = "d"
  validation {
    regex = "^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$"
    error = "Slot D subdomain must contain only alphanumeric characters and dashes, start and end with alphanumeric characters, and be 1-63 characters long."
  }
}

data "coder_parameter" "slot_e_subdomain" {
  name         = "SLOT_E_SUBDOMAIN"
  display_name = "Slot E Subdomain"
  description  = "Subdomain for slot E (alphanumeric, dashes, max 63 chars)"
  type         = "string"
  mutable      = true
  default      = "e"
  validation {
    regex = "^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$"
    error = "Slot E subdomain must contain only alphanumeric characters and dashes, start and end with alphanumeric characters, and be 1-63 characters long."
  }
}
 
  

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}
 
data "coder_workspace" "me" {}

# NOTE: the workspace owner details were previously included in coder_workspace.owner
# but those params are now deprecated in favour of "coder_workspace_owner"
data "coder_workspace_owner" "me" {} 

resource "coder_agent" "main" {
  os                     = "linux"
  arch                   = "amd64"  
 

  #  Note:  the startup script is now defined as a separate resource.
  # startup_script           = <<-EOT
  #   bash -lc '/home/coder/coder/startup.sh'
  # EOT
  # startup_script_behavior  = "blocking" 
 
  # TEST: this may help to tell VS Code Desktop which folder to open
  dir  = "/home/coder"

  display_apps {
    vscode          = false
    vscode_insiders = false
    web_terminal    = false
    ssh_helper      = false
  }

   
  env = {
    GIT_AUTHOR_NAME     = "${data.coder_workspace_owner.me.name}"
    GIT_COMMITTER_NAME  = "${data.coder_workspace_owner.me.name}"
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"  
    WORKSPACE_NAME      = "${data.coder_workspace.me.name}"
    WORKSPACE_ID        = "${data.coder_workspace.me.id}"
    ADMIN_URL           = "https://admin--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    PUBLIC_URL          = "https://public--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    EDITOR_URL          = "https://${local.workspace_slug}--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    SETTINGS_URL        = "https://${local.ixd_domain}/@${local.username}/${data.coder_workspace.me.name}"
    USERNAME            = "${local.username}"
    IXD_DOMAIN          = "${local.ixd_domain}"   

    # Slot subdomain parameters
    SLOT_A_SUBDOMAIN    = "${data.coder_parameter.slot_a_subdomain.value}"
    SLOT_B_SUBDOMAIN    = "${data.coder_parameter.slot_b_subdomain.value}"
    SLOT_C_SUBDOMAIN    = "${data.coder_parameter.slot_c_subdomain.value}"
    SLOT_D_SUBDOMAIN    = "${data.coder_parameter.slot_d_subdomain.value}"
    SLOT_E_SUBDOMAIN    = "${data.coder_parameter.slot_e_subdomain.value}"
    
    # Slot URL parameters
    SLOT_A_URL          = "https://${data.coder_parameter.slot_a_subdomain.value}--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    SLOT_B_URL          = "https://${data.coder_parameter.slot_b_subdomain.value}--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    SLOT_C_URL          = "https://${data.coder_parameter.slot_c_subdomain.value}--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    SLOT_D_URL          = "https://${data.coder_parameter.slot_d_subdomain.value}--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    SLOT_E_URL          = "https://${data.coder_parameter.slot_e_subdomain.value}--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    
    # Database configuration
    POSTGRES_HOST       = "localhost"
    POSTGRES_PORT       = "5432"
    POSTGRES_DB         = "workspace_db"
    POSTGRES_USER       = "coder"
    POSTGRES_PASSWORD   = "coder_dev_password"
    DATABASE_URL        = "postgresql://coder:coder_dev_password@localhost:5432/workspace_db"

    WORKSPACE_AGENT     = "main" 
  }
 
 
} 

resource "coder_script" "startup" {
  agent_id           = coder_agent.main.id
  display_name       = "Workspace Startup"
  run_on_start       = true              # run on workspace start
  start_blocks_login = true              # block until finished (recommended)
  # Use replace(...) to strip any accidental CRLFs that can break Bash (e.g., invalid option name for pipefail)
  script             = replace(file("${path.module}/startup.sh"), "\r", "")
}

# Detached runtime services (non-blocking). These run concurrently on start and
# each script is responsible for its own readiness gating.
# Admin service starts PM2 ecosystem (admin server + placeholder server)
resource "coder_script" "service_admin" {
  agent_id           = coder_agent.main.id
  display_name       = "Admin Service"
  run_on_start       = true
  start_blocks_login = false
  script             = replace(file("${path.module}/admin.sh"), "\r", "")
}

# PM2 provides built-in process monitoring, so no separate monitor needed
# resource "coder_script" "service_monitor" {
#   agent_id           = coder_agent.main.id
#   display_name       = "Process Monitor"
#   run_on_start       = true
#   start_blocks_login = false
#   script             = replace(file("${path.module}/monitor.sh"), "\r", "")
# }

# resource "coder_script" "service_pgadmin" {
#   agent_id           = coder_agent.main.id
#   display_name       = "pgAdmin"
#   run_on_start       = true
#   start_blocks_login = false
#   script             = replace(file("${path.module}/pgadmin.sh"), "\r", "")
# }
 

# resource "coder_script" "service_pgweb" {
#   agent_id           = coder_agent.main.id
#   display_name       = "PGWeb"
#   run_on_start       = true
#   start_blocks_login = false
#   script             = replace(file("${path.module}/pgweb.sh"), "\r", "")
# }
 

# The placeholder server is now managed by PM2 via the ecosystem configuration
# resource "coder_script" "service_placeholders" {
#   agent_id           = coder_agent.main.id
#   display_name       = "Slot Placeholders"
#   run_on_start       = true
#   start_blocks_login = false
#   script             = replace(file("${path.module}/placeholders.sh"), "\r", "")
# }

# NOTE coder modules are frequently updated. 
# note that version  = "1.0.30" refers to the entire module repo rather than the specific module
# you can see a complete history of module changes here:/
# https://github.com/coder/modules/compare/v1.0.6...v1.0.30
# See also, more specifically:
# https://github.com/coder/modules/commits/main/cursor
# https://github.com/coder/modules/commits/main/vscode-web

 

module "vscode-web" {
  source         = "registry.coder.com/modules/vscode-web/coder"
  version        = "1.0.30"
  agent_id       = coder_agent.main.id
  folder   = "/home/coder"
  extensions     = ["github.copilot", "dbcode.dbcode", "github.vscode-github-actions", "github.remotehub"]
  settings = {
      "workbench.colorTheme": "Default Dark Modern",
      "workbench.colorCustomizations": {
          "statusBar.background" : "#1A1A1A",
          "statusBar.noFolderBackground" : "#212121",
          "statusBar.debuggingBackground": "#263238"
      },
      "files.exclude": {
          "**/*.cache": true,
          "**/*.config": true,
          "**/*.local": true,
          "**/*.bashrc": true,
          "**/*.npm": true,
          "**/*filebrowser.db": true,
          "**/*lost+found": true,
          "**/*.bash_history": true,
          "**/*.vscode": true,
          "**/*.dotnet": true,
          "**/*.vscode-server": true,
          "**/*.wget-hsts": true
      },
      "workbench.startupEditor" : "readme",
      "security.workspace.trust.enabled": false,
      "editor.defaultFormatter": "esbenp.prettier-vscode",
      "codetogether.userName": "${local.username}",
      "remote.portsAttributes": {
          "0-65535":{
              "onAutoForward":"silent"
          }
      },
      "remote.SSH.remotePlatform": {
          "*.ixdcoder.com": "linux",
      },
      "github.copilot.enable": {
          "*": true,
          "sql": false
      },
      "github.gitAuthentication": true,
      "git.autofetch": true,
      "git.enableSmartCommit": true,
      "github.copilot.advanced": {},
      "workbench.welcomePage.walkthroughs.openOnInstall": false,
      "workbench.startupEditor": "welcomePage",
      "accounts.sync": "on",
      "settingsSync.keybindingsPerPlatform": false
  } 
  accept_license = true
}
  

resource "coder_app" "admin" {
  agent_id     = coder_agent.main.id
  slug         = "admin"
  display_name = "Settings"
  url          = "http://localhost:9000"
  icon         = "/icon/widgets.svg"
  subdomain    = true
  share        = "owner"
  healthcheck {
    url       = "http://localhost:9000"
    interval  = 10
    threshold = 5
  }
}

# resource "coder_app" "pgadmin" {
#   agent_id     = coder_agent.main.id
#   slug         = "pgadmin"
#   display_name = "PGAdmin"
#   url          = "http://localhost:5050"
#   icon         = "/icon/database.svg"
#   subdomain    = true
#   share        = "owner"
#   healthcheck {
#     url       = "http://localhost:5050"
#     interval  = 15
#     threshold = 3
#   }
# }

# resource "coder_app" "pgweb" {
#   agent_id     = coder_agent.main.id
#   slug         = "pgweb"
#   display_name = "PGWeb"
#   url          = "http://localhost:8081"
#   icon         = "/icon/database.svg"
#   subdomain    = true
#   share        = "owner"
#   healthcheck {
#     url       = "http://localhost:8081"
#     interval  = 15
#     threshold = 3
#   }
# }

# Individual slot apps
resource "coder_app" "slot_a" {
  agent_id     = coder_agent.main.id
  slug         = data.coder_parameter.slot_a_subdomain.value
  display_name = "${data.coder_parameter.slot_a_subdomain.value}"
  url          = "http://localhost:3001"
  icon         = "/icon/nodejs.svg"
  subdomain    = true
  share        = "public"
  healthcheck {
    url       = "http://localhost:3001"
    interval  = 10
    threshold = 3
  }
}

resource "coder_app" "slot_b" {
  agent_id     = coder_agent.main.id
  slug         = data.coder_parameter.slot_b_subdomain.value
  display_name = "${data.coder_parameter.slot_b_subdomain.value}"
  url          = "http://localhost:3002"
  icon         = "/icon/nodejs.svg"
  subdomain    = true
  share        = "public"
  healthcheck {
    url       = "http://localhost:3002"
    interval  = 10
    threshold = 3
  }
}

resource "coder_app" "slot_c" {
  agent_id     = coder_agent.main.id
  slug         = data.coder_parameter.slot_c_subdomain.value
  display_name = "${data.coder_parameter.slot_c_subdomain.value}"
  url          = "http://localhost:3003"
  icon         = "/icon/nodejs.svg"
  subdomain    = true
  share        = "public"
  healthcheck {
    url       = "http://localhost:3003"
    interval  = 10
    threshold = 3
  }
}

resource "coder_app" "slot_d" {
  agent_id     = coder_agent.main.id
  slug         = data.coder_parameter.slot_d_subdomain.value
  display_name = "${data.coder_parameter.slot_d_subdomain.value}"
  url          = "http://localhost:3004"
  icon         = "/icon/nodejs.svg"
  subdomain    = true
  share        = "public"
  healthcheck {
    url       = "http://localhost:3004"
    interval  = 10
    threshold = 3
  }
}

resource "coder_app" "slot_e" {
  agent_id     = coder_agent.main.id
  slug         = data.coder_parameter.slot_e_subdomain.value
  display_name = "${data.coder_parameter.slot_e_subdomain.value}"
  url          = "http://localhost:3005"
  icon         = "/icon/nodejs.svg"
  subdomain    = true
  share        = "public"
  healthcheck {
    url       = "http://localhost:3005"
    interval  = 10
    threshold = 3
  }
}

 
# NOTE: the storage amount is hard coded to 1Gigabyte here
# this is different from the NodeJS workspace, where it is parameterized.
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-home" 
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}" 
      "app.kubernetes.io/part-of"  = "coder"
      //Coder-specific labels.
      "com.coder.resource"       = "true"
      "com.coder.workspace.id"   = data.coder_workspace.me.id
      "com.coder.workspace.name" = data.coder_workspace.me.name
      "com.coder.user.id"        = data.coder_workspace_owner.me.id
      "com.coder.user.username"  = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim.home
  ]
  wait_for_rollout = false
  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}" 
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    # replicas = data.coder_workspace.me.start_count
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "coder-workspace"
      }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "coder-workspace"
        }
      }
      spec {
        security_context {
          run_as_user = 1000
          fs_group    = 1000
        }

        container {
          name              = "dev"
          # image             = "codercom/enterprise-node:ubuntu"
          # image             = "nsitu/node-devenv-2024:latest"
          image  = "nsitu/coder-paas:latest"
          # Image Pull Policy: Always / IfNotPresent/ Never
          # see also: https://kubernetes.io/docs/concepts/containers/images/#image-pull-policy 
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user = "1000"
          }
          # TODO: maybe it is convenient to inject other env variables here?
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          resources {
            requests = {
              "cpu"    = "500m"
              "memory" = "1Gi"
            }
            limits = {
              "cpu"    = "2000m"
              "memory" = "4Gi"
            }
          }
          volume_mount {
            # IMPORTANT the mount path determines which files are persisted 
            # ie. saved between restarts.  
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
            read_only  = false
          }
        }

        affinity {
          // This affinity attempts to spread out all workspace pods evenly across
          // nodes.
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
