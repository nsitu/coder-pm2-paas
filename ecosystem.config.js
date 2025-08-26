module.exports = {
    apps: [
        {
            name: 'admin-server',
            script: '/home/coder/srv/admin/server.js',
            instances: 1,
            autorestart: true,
            watch: false,
            max_restarts: 10,
            env: {
                NODE_ENV: 'development',
                PORT: '9000'
            },
            error_file: '/home/coder/logs/pm2/admin-error.log',
            out_file: '/home/coder/logs/pm2/admin-out.log',
            log_file: '/home/coder/logs/pm2/admin.log',
            time: true
        },
        {
            name: 'slot-web-server',
            script: '/home/coder/srv/server/server.js',
            instances: 1,
            autorestart: true,
            watch: false,
            max_restarts: 10,
            env: {
                NODE_ENV: 'development'
            },
            error_file: '/home/coder/logs/pm2/slot-web-server-error.log',
            out_file: '/home/coder/logs/pm2/slot-web-server-out.log',
            log_file: '/home/coder/logs/pm2/slot-web-server.log',
            time: true
        }
        // Note: Individual slot configurations are now managed dynamically by add-slot.js
        // The placeholder server above handles empty slots automatically via PM2
    ]
};
