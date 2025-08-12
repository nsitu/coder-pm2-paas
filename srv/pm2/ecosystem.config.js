// /srv/pm2/ecosystem.config.js
module.exports = {
    apps: [
        {
            name: "webhook",
            script: "node",
            args: "/home/coder/srv/webhook/server.js",
            env: {
                WEBHOOK_PORT: "4600"
            }
        }

        // Entries appended by deploy script, e.g.:
        // {
        //   name: "repo-name",
        //   script: "npm",
        //   args: "start",
        //   cwd: "/srv/apps/repo-name",
        //   env: {
        //     PORT: 3001,
        //     BASE_PATH: "/repo-name"
        //   },
        //   max_memory_restart: "250M",
        //   instances: 1,
        //   exec_mode: "fork",
        //   restart_delay: 2000
        // }
    ]
}
