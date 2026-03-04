#!/bin/bash

# Create group if needed
if ! getent group $PGID >/dev/null; then
    groupadd -g $PGID huntarr
fi

# Create user if needed
if ! id -u $PUID >/dev/null 2>&1; then
    useradd -u $PUID -g $PGID -m -s /bin/bash huntarr
fi

# Fix ownership
chown -R $PUID:$PGID /config /app

# Apply UMASK
umask $UMASK

# Drop privileges and run the app
exec gosu $PUID:$PGID "$@"
