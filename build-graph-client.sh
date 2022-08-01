#!/bin/bash
# NOTE: You may have to run the `export` lines below manually before executing this script!

# Set this to 0 if you want to build using a locally hosted graph node:
BUILD_USING_LIVE_VERSION=1

if [ $BUILD_USING_LIVE_VERSION -eq 1 ]; then
    GRAPH_GOERLI_HANDLER_ENDPOINT="https://api.thegraph.com/subgraphs/name/connext/nxtp-amarok-runtime-test-goerli"
    export GRAPH_1337_ENDPOINT=${GRAPH_GOERLI_HANDLER_ENDPOINT}
    export GRAPH_1338_ENDPOINT=${GRAPH_GOERLI_HANDLER_ENDPOINT}
else
    export GRAPH_1337_ENDPOINT="http://localhost:8010/subgraphs/name/connext/nxtp"
    export GRAPH_1338_ENDPOINT="http://localhost:9010/subgraphs/name/connext/nxtp"

    # bring up chains/graph node/ipfs
    docker compose -f docker-compose.chains.yaml up -d

    # build subgraph
    yarn workspace @connext/nxtp-subgraph prepare:v0
    yarn workspace @connext/nxtp-subgraph codegen

    # create/deploy subgraphs to graph nodes
    yarn workspace @connext/nxtp-subgraph create-local-1337
    yarn workspace @connext/nxtp-subgraph deploy-local-1337 -l v0.0.1
    yarn workspace @connext/nxtp-subgraph create-local-1338
    yarn workspace @connext/nxtp-subgraph deploy-local-1338 -l v0.0.1
fi

# generate client
echo "Building graph client..."
yarn workspace @connext/nxtp-adapters-subgraph run build-client
