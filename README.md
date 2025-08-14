# coder-pm2-paas

A Platform-as-a-Service (PaaS) solution built for [Coder](https://coder.com) workspaces that enables automatic deployment of Node.js applications via GitHub webhooks. This Docker image provides a complete deployment environment with PM2 process management, NGINX reverse proxy, and automated CI/CD capabilities.

## Features

### 🚀 Automated Deployment Pipeline
- **GitHub Webhook Integration**: Automatically deploys Node.js apps on git push events
- **Multi-App Support**: Deploy and manage multiple Node.js applications simultaneously
- **Zero-Downtime Deployments**: Uses PM2's reload capabilities for seamless updates
- **Port Management**: Automatic port allocation and conflict resolution
- **Branch-Specific Deployments**: Deploy from any git branch (default: main)

### 🔧 Infrastructure Components
- **PM2 Process Manager**: Production-ready Node.js process management with clustering, monitoring, and auto-restart
- **NGINX Reverse Proxy**: High-performance web server with WebSocket support and SSL termination ready
- **Kubernetes-Ready**: Designed for deployment on Kubernetes with persistent volumes and resource limits
- **VS Code Integration**: Built-in VS Code web editor with customized settings and extensions

### 🏗️ Project Structure
- **Persistent Storage**: Applications and configurations survive workspace restarts
- **Modular Architecture**: Clean separation between deployment scripts, configs, and running applications
- **Security**: Repository allowlisting, SSH key management, and isolated app environments

## Quick Start

### Setting Up the Workspace
1. Deploy this Coder template to your Kubernetes cluster
2. Configure allowed repositories in the `ALLOWED_REPOS` parameter
3. Access your workspace via the provided VS Code URL

### Deploying an Application
1. **Via Webhook** (Recommended): Configure a GitHub webhook pointing to `https://your-workspace-url/__hook/github`
2. **Manual Deployment**: Use the deploy script directly:
   ```bash
   /home/coder/srv/scripts/slot-deploy.sh app-name https://github.com/owner/repo.git main
   ```

### Accessing Your Apps
- **Public URL**: `https://public--main--workspace--username.domain/app-name/`
- **Development**: `https://workspace-slug--main--workspace--username.domain/app-name/`

## Architecture

### Directory Structure
```
srv/
├── apps/           # Deployed applications
├── deploy/         # Deployment scripts and port mappings
├── docs/           # Static documentation
├── nginx/          # NGINX configuration and logs
├── pm2/            # PM2 ecosystem and management scripts
└── webhook/        # GitHub webhook server
```

### Core Components

#### Scripts Directory (`srv/scripts/`)

Contains all operational scripts for the PaaS system:
- **`slot-deploy.sh`** - Enhanced deployment script with comprehensive features
- **`process-manager.sh`** - Process management system replacing PM2
- **`config-manager.js`** - Configuration management and validation
- **`health-check.sh`** - System health monitoring and diagnostics
- Clones/updates git repositories
- Installs dependencies and runs build scripts
- Configures NGINX routes and PM2 processes
- Manages port allocation and process lifecycle

#### Webhook Server (`srv/webhook/server.js`)
- Listens for GitHub push events
- Validates repository permissions against allowlist
- Triggers deployments with SHA-based deduplication
- Provides deployment status and error reporting

#### Process Management (`srv/pm2/`)
- Dynamic PM2 ecosystem configuration
- Application-specific environment variables
- Memory limits and restart policies
- Process monitoring and logging

#### Web Server (`srv/nginx/`)
- Reverse proxy to PM2-managed applications
- WebSocket support for real-time applications
- Static file serving and documentation
- Custom error pages and security headers

## Configuration

### Environment Variables
- `ALLOWED_REPOS`: JSON array or CSV list of allowed GitHub repositories
- `DEFAULT_BRANCH`: Default git branch for deployments (default: main)
- `PUBLIC_URL`: Public-facing URL for deployed applications
- `EDITOR_URL`: VS Code editor URL for development

### Coder Template Parameters
- Repository allowlist configuration
- Kubernetes namespace and resource limits
- Persistent volume size and storage class
- VS Code extensions and settings

## Security Features

- **Repository Allowlisting**: Only permitted repositories can be deployed
- **SSH Key Management**: Automatic SSH key configuration for private repositories
- **Process Isolation**: Each application runs in its own PM2 process
- **Resource Limits**: CPU and memory constraints per workspace
- **Network Security**: Internal-only webhook endpoint with method validation

## Use Cases

### Educational Environments
- Student project hosting and automatic grading
- Portfolio deployment for coding bootcamps
- Collaborative development with instant preview

### Development Teams
- Feature branch previews and testing
- Rapid prototyping and iteration
- Integration testing environments

### Personal Projects
- Blog and portfolio hosting
- API development and testing
- Microservices development

## Technical Requirements

- Kubernetes cluster with persistent volume support
- Coder deployment with workspace templates
- GitHub repository with webhook permissions
- Node.js applications with `package.json` and npm scripts

## Project Folders

### `coder/`
Contains Coder workspace configuration files:
- `main.tf`: Terraform configuration for Kubernetes deployment
- `startup.sh`: Workspace initialization and service startup script

### `srv/`
Contains the complete PaaS infrastructure that gets deployed inside workspaces:
- Deployment automation, process management, and web server configuration
- Persistent across workspace restarts via mounted volumes

## License

This project provides a complete containerized PaaS solution for educational and development environments, combining the power of Coder workspaces with production-ready deployment automation.
