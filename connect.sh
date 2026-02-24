#!/bin/bash
# Usage: ./connect.sh <user>
#   son   — human admin
#   anton — bot user
if [ -z "$1" ]; then
  echo "Usage: ./connect.sh <user>"
  echo "  son   — human admin"
  echo "  anton — bot user"
  exit 1
fi
exec "$(dirname "$0")/infra/oracle/connect-nanoclaw.sh" "$@"
