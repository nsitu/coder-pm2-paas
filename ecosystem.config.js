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
            error_file: '/home/coder/data/logs/pm2/admin-error.log',
            out_file: '/home/coder/data/logs/pm2/admin-out.log',
            log_file: '/home/coder/data/logs/pm2/admin.log',
            time: true
        },
        {
            name: 'placeholder-server',
            script: '/home/coder/srv/placeholders/server.js',
            instances: 1,
            autorestart: true,
            watch: false,
            max_restarts: 10,
            env: {
                NODE_ENV: 'development'
            },
            error_file: '/home/coder/data/logs/pm2/placeholder-error.log',
            out_file: '/home/coder/data/logs/pm2/placeholder-out.log',
            log_file: '/home/coder/data/logs/pm2/placeholder.log',
            time: true
        }
        // Note: Individual slot configurations are now managed dynamically by add-slot.js
        // The placeholder server above handles empty slots automatically via PM2
    ]
};
