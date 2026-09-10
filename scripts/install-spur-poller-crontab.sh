#!/bin/sh
set -eu

cat > /tmp/slurm-gha-pollers.cron <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
*/10 * * * * /bin/bash -lc '/home/xihuang/slurm-gha/ensure-spur-di-poller.sh >> /home/xihuang/slurm-gha/logs/poller-watchdog.log 2>&1'
@reboot /bin/bash -lc '/home/xihuang/slurm-gha/ensure-spur-di-poller.sh >> /home/xihuang/slurm-gha/logs/poller-watchdog.log 2>&1'
*/10 * * * * /bin/bash -lc '/home/xihuang/slurm-gha/ensure-linux-do-exp-poller.sh >> /home/xihuang/slurm-gha/logs/poller-linux-do-exp-watchdog.log 2>&1'
@reboot /bin/bash -lc '/home/xihuang/slurm-gha/ensure-linux-do-exp-poller.sh >> /home/xihuang/slurm-gha/logs/poller-linux-do-exp-watchdog.log 2>&1'
EOF

crontab /tmp/slurm-gha-pollers.cron
rm -f /tmp/slurm-gha-pollers.cron
crontab -l
