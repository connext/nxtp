#!/bin/bash
##### Config Variables
LOCALHOST="127.0.0.1"
# LOCALHOST="localhost"
SEQUENCER_PORT="8081"
ROUTER_PORT="8080"
DEFAULT_MNEMONIC="candy maple cake sugar pudding cream honey rich smooth crumble sweet treat"
router_publisher_image="${ROUTER_PUBLISHER_IMAGE:-'router-publisher:latest'}"
router_subscriber_image="${ROUTER_SUBSCRIBER_IMAGE:-'router-subscriber:latest'}"
sequencer_publisher_image="${SEQUENCER_PUBLISHER_IMAGE:-'sequencer-publisher:latest'}"
sequencer_subscriber_image="${SEQUENCER_SUBSCRIBER_IMAGE:-'sequencer-subscriber:latest'}"
relayer_image="${RELAYER_IMAGE:-'relayer:latest'}"
cartographer_transfers_image="${CARTOGRAPHER_TRANSFERS_IMAGE:-'cartographer-transfers:latest'}"
cartographer_routers_image="${CARTOGRAPHER_ROUTERS_IMAGE:-'cartographer-routers:latest'}"
lighthouse_image="${LIGHTHOUSE_IMAGE:-'lighthouse:latest'}"
WEB3_SIGNER_PRIVATE_KEY="0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"
RELAYER_URL="http://relayer:8082"
#####

##### Global .env Configuration
echo "
# Global test environment
ROUTER_PORT=${ROUTER_PORT}
SEQUENCER_PORT=${SEQUENCER_PORT}

# Agent configuration
NXTP_SEQUENCER=http://${LOCALHOST}:${SEQUENCER_PORT}
NXTP_MNEMONIC=${DEFAULT_MNEMONIC}
NXTP_SERVER_HOST=http://${LOCALHOST}
NXTP_SERVER_PORT=${ROUTER_PORT}

SEQ_SERVER_HOST=http://${LOCALHOST}
SEQ_SERVER_PORT=${SEQUENCER_PORT}
SEQ_ENVIRONMENT=production
SEQ_RELAYER_URL=${RELAYER_URL}

NXTP_CONFIG=config.local.json
SEQ_CONFIG=config.local.json
RELAYER_CONFIG=config.local.json

NXTP_ENVIRONMENT=production
NXTP_NOMAD_ENVIRONMENT=staging

MNEMONIC=${DEFAULT_MNEMONIC}
WEB3_SIGNER_PRIVATE_KEY=${WEB3_SIGNER_PRIVATE_KEY}

# Images used for building docker containers
ROUTER_PUBLISHER_IMAGE=${router_publisher_image}
ROUTER_SUBSCRIBER_IMAGE=${router_subscriber_image}
SEQUENCER_PUBLISHER_IMAGE=${sequencer_publisher_image}
SEQUENCER_SUBSCRIBER_IMAGE=${sequencer_subscriber_image}
RELAYER_IMAGE=${relayer_image}
CARTOGRAPHER_TRANSFERS_IMAGE=${cartographer_transfers_image}
CARTOGRAPHER_ROUTERS_IMAGE=${cartographer_routers_image}
LIGHTHOUSE_IMAGE=${lighthouse_image}

# Optional:
# AUCTION_ROUND_DEPTH
# NXTP_SUBGRAPH_POLL_INTERVAL
# NXTP_CACHE_POLL_INTERVAL
" > .env
#####

##### Local chains, graph nodes, and IPFS.
echo "Starting 1337 and 1338 local chains..."
docker compose -f docker-compose.chains.yaml up -d --force-recreate
sleep 5
#####

##### Contract Deployments
echo "Deploying contracts to 1337..."
MNEMONIC=${DEFAULT_MNEMONIC} ENV=production CHAIN_ID=1337 ETH_PROVIDER_URL=http://${LOCALHOST}:8547 yarn workspace @connext/nxtp-contracts hardhat deploy --network localhost --tags local
echo "Deployed contracts to 1337"

echo "Deploying contracts to 1338..."
MNEMONIC=${DEFAULT_MNEMONIC} ENV=production CHAIN_ID=1338 ETH_PROVIDER_URL=http://${LOCALHOST}:8546 yarn workspace @connext/nxtp-contracts hardhat deploy --network localhost --tags local
echo "Deployed contracts to 1338"
#####

##### Subgraph Deployments
echo "Building subgraph..."
yarn workspace @connext/nxtp-subgraph prepare:v0
yarn workspace @connext/nxtp-subgraph codegen
echo "Built subgraph"

echo "Deploying subgraph to 1337..."
yarn workspace @connext/nxtp-subgraph create-local-1337
yarn workspace @connext/nxtp-subgraph deploy-local-1337 -l v0.0.1
echo "Deployed subgraph to 1337"

echo "Deploying subgraph to 1338..."
yarn workspace @connext/nxtp-subgraph create-local-1338
yarn workspace @connext/nxtp-subgraph deploy-local-1338 -l v0.0.1
echo "Deployed subgraph to 1338"
#####

##### Off-Chain Agents
echo "Starting services and off-chain agents..."
docker compose -f docker-compose.services.yaml up -d --force-recreate
sleep 5
#####
