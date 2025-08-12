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
 
 

data "coder_parameter" "git_repo" {
  name                = "git_repo"
  display_name        = "App #1 Git Repository"
  description = "URL for a Git Repository to deploy as a NodeJS app."
  icon        = "/icon/git.svg"
  type        = "string"
  mutable     = true
  default     = "https://bender.sheridanc.on.ca/sikkemha/nodejs.git" 
}
data "coder_parameter" "allowed_repos" {
  name         = "ALLOWED_REPOS"
  display_name = "Allowed GitHub repos (owner/repo)"
  type         = "list(string)"
  mutable      = true
  default      = jsonencode([
    "https://github.com/nsitu/express-hello-world"
  ])
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
  startup_script         = replace(file("${path.module}/startup.sh"), "\r", "")
 
  # TEST: this may help to tell VS Code Desktop which folder to open
  dir  = "/home/coder/${data.coder_workspace_owner.me.name}"

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
    GIT_REPO            = "${data.coder_parameter.git_repo.value}" 
    WORKSPACE_NAME      = "${data.coder_workspace.me.name}"
    WORKSPACE_ID        = "${data.coder_workspace.me.id}"
    PUBLIC_URL          = "https://public--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    EDITOR_URL          = "https://${local.workspace_slug}--main--${lower(data.coder_workspace.me.name)}--${local.username}.${local.ixd_domain}/"
    SETTINGS_URL        = "https://${local.ixd_domain}/@${local.username}/${data.coder_workspace.me.name}"
    USERNAME            = "${local.username}"
    # TEMPLATE_MODE       = "${data.coder_parameter.template_mode.value}"
    PORT                = 8080   

    ALLOWED_REPOS          = "${data.coder_parameter.allowed_repos.value}" 
    DEFAULT_BRANCH         = "main" 

  }
 
 
}
# It is vital that the workspace folder in the url 
# Matches the folder that we are actually persisting. 
# /home/coder/${data.coder_workspace_owner.me.name}

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
  folder   = "/home/coder/${data.coder_workspace_owner.me.name}"
  # extensions     = ["github.copilot"]
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
      }
  } 
  accept_license = true
}
 
  

resource "coder_app" "webapp" {
  agent_id     = coder_agent.main.id
  slug         = "public"
  display_name = "Public URL"
  url          = "http://localhost:8080"
  icon         = "https://bender.sheridanc.on.ca/sikkemha/svg-icons/-/raw/main/html.svg"
  subdomain    = true
  share        = "public"
  healthcheck {
    # Note: this health check assumes that LiveServer is running,
    # as indeed it should be based on startup.sh
    url       = "http://localhost:8080"
    interval  = 5
    threshold = 6
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
        storage = "512Mi"
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
          image  = "nsitu/coder-pm2-paas:latest"
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
              "cpu"    = "250m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "1000m"
              "memory" = "2Gi"
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
