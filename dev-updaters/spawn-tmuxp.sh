#!/usr/bin/env bash
(
    # set -euo pipefail
    # export CURRENT_WORKDIR="/mnt/exam"
    # mkdir -p $CURRENT_WORKDIR 2>/dev/null || true
    # mkdir /tmp/current_dashboard
    # cp -r /mnt/dashboard_lxc/ /tmp/current_dashboard 
    # cd /tmp/current_dashboard/dashboard_lxc/
    # find . -type f -exec sed -i "s|REPLACE_WITH_PATH_CURRENT_CHALLENGE|${CURRENT_WORKDIR}|g" {} +
    DISABLE_AUTO_TITLE='true' tmuxp load ./start-all.yaml -d
)
