# Fastfetch SSH Interactive Login Banner
# Only display when standard output is connected to a terminal (interactive session).
# This strictly prevents breaking SCP, SFTP, WinSCP, rsync, and non-interactive scripts.
if [ -t 1 ] && [ -x /usr/bin/fastfetch ]; then
    /usr/bin/fastfetch
fi
