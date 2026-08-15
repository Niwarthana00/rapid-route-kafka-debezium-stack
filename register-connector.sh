#!/usr/bin/env bash
set -euo pipefail


CONNECT_URL="http://localhost:8083"
CONNECTOR_NAME="bus-enterprise-connector"
CONFIG_FILE="$(dirname "$0")/connectors/bus-db-connector.json"

echo "Waiting for Kafka Connect to be ready at ${CONNECT_URL} ..."
until curl -s -o /dev/null -w "%{http_code}" "${CONNECT_URL}/connectors" | grep -q "200"; do
  sleep 3
  echo "  still waiting..."
done
echo "Connect is up."

if curl -s "${CONNECT_URL}/connectors/${CONNECTOR_NAME}" | grep -q "\"name\""; then
  echo "Connector '${CONNECTOR_NAME}' already exists — updating its config."
  curl -s -X PUT \
    -H "Content-Type: application/json" \
    --data "$(python3 -c "import json,sys; print(json.dumps(json.load(open('${CONFIG_FILE}'))['config']))")" \
    "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/config" | python3 -m json.tool
else
  echo "Creating connector '${CONNECTOR_NAME}'."
  curl -s -X POST \
    -H "Content-Type: application/json" \
    --data @"${CONFIG_FILE}" \
    "${CONNECT_URL}/connectors" | python3 -m json.tool
fi

echo ""
echo "Check status with:"
echo "  curl -s ${CONNECT_URL}/connectors/${CONNECTOR_NAME}/status | python3 -m json.tool"
