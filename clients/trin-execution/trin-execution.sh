#!/bin/bash

# Startup script to initialize and boot a trin-execution instance.
#
# This script assumes the following files:
#  - `trin-execution` binary is located in the filesystem root
#  - `genesis.json` file is located in the filesystem root (mandatory)
#  - `chain.rlp` file is located in the filesystem root (optional)
#  - `blocks` folder is located in the filesystem root (optional)
#
# This script can be configured using the following environment variables:
#
#  - HIVE_BOOTNODE             enode URL of the remote bootstrap node
#  - HIVE_NETWORK_ID           network ID number to use for the eth protocol
#  - HIVE_FORK_HOMESTEAD       block number of the homestead transition
#  - HIVE_FORK_DAO_BLOCK       block number of the DAO hard-fork transition
#  - HIVE_FORK_TANGERINE       block number of TangerineWhistle
#  - HIVE_FORK_SPURIOUS        block number of SpuriousDragon
#  - HIVE_FORK_BYZANTIUM       block number for Byzantium transition
#  - HIVE_FORK_CONSTANTINOPLE  block number for Constantinople transition
#  - HIVE_FORK_PETERSBURG      block number for ConstantinopleFix/Petersburg transition
#  - HIVE_FORK_ISTANBUL        block number for Istanbul transition
#  - HIVE_FORK_MUIR_GLACIER    block number for MuirGlacier transition
#  - HIVE_SHANGHAI_TIMESTAMP   timestamp for Shanghai transition
#  - HIVE_CANCUN_TIMESTAMP     timestamp for Cancun transition
#  - HIVE_LOGLEVEL             client log level
#
# These flags are NOT supported by trin-execution
#
#  - HIVE_GRAPHQL_ENABLED      turns on GraphQL server
#  - HIVE_CLIQUE_PRIVATEKEY    private key for clique mining
#  - HIVE_NODETYPE             sync and pruning selector (archive, full, light)
#  - HIVE_MINER                address to credit with mining rewards
#  - HIVE_MINER_EXTRA          extra-data field to set for newly minted blocks

# Immediately abort the script on any error encountered
set -ex

# no ansi colors
export RUST_LOG_STYLE=never

trin_execution=/usr/bin/trin-execution

TRIN_LOGLEVEL=info
case "$HIVE_LOGLEVEL" in
    0|1) TRIN_LOGLEVEL=error ;;
    2)   TRIN_LOGLEVEL=warn ;;
    3)   TRIN_LOGLEVEL=info ;;
    4)   TRIN_LOGLEVEL=debug ;;
    5)   TRIN_LOGLEVEL=trace ;;
esac

# Create the data directory.
DATADIR="/trin-execution-hive-datadir"
mkdir $DATADIR
FLAGS="$FLAGS --data-dir $DATADIR --save-blocks"

# TODO If a specific network ID is requested, use that
#if [ "$HIVE_NETWORK_ID" != "" ]; then
#    FLAGS="$FLAGS --networkid $HIVE_NETWORK_ID"
#else
#    FLAGS="$FLAGS --networkid 1337"
#fi

# Configure the chain.
mv /genesis.json /genesis-input.json
jq -f /mapper.jq /genesis-input.json > /genesis.json

# Dump genesis.
if [ "$HIVE_LOGLEVEL" -lt 4 ]; then
    echo "Supplied genesis state (trimmed, use --sim.loglevel 4 or 5 for full output):"
    jq 'del(.alloc[] | select(.balance == "0x123450000000000000000"))' /genesis.json
else
    echo "Supplied genesis state:"
    cat /genesis.json
fi

echo "Command flags till now:"
echo $FLAGS

# Initialize the local testchain with the genesis state
echo "Initializing database with genesis state..."
RUST_LOG=$TRIN_LOGLEVEL $trin_execution $FLAGS --chain /genesis.json init

# make sure we use the same genesis each time
FLAGS="$FLAGS --chain /genesis.json"

# Don't immediately abort, some imports are meant to fail
set +ex

# Load the test chain if present
echo "Loading initial blockchain..."
if [ -f /chain.rlp ]; then
    RUST_LOG=$TRIN_LOGLEVEL $trin_execution $FLAGS import /chain.rlp
else
    echo "Warning: chain.rlp not found."
fi

# Load the remainder of the test chain
echo "Loading remaining individual blocks..."
if [ -d /blocks ]; then
    echo "Loading remaining individual blocks..."
    for file in $(ls /blocks | sort -n); do
        echo "Importing " $file
        RUST_LOG=$TRIN_LOGLEVEL import $FLAGS /blocks/$file
    done
else
    echo "Warning: blocks folder not found."
fi

# Only set boot nodes in online steps
# It doesn't make sense to dial out, use only a pre-set bootnode.
if [ "$HIVE_BOOTNODE" != "" ]; then
    FLAGS="$FLAGS --bootnodes=$HIVE_BOOTNODE"
fi

# Configure any mining operation
# TODO
#if [ "$HIVE_MINER" != "" ]; then
#    FLAGS="$FLAGS --mine --miner.etherbase $HIVE_MINER"
#fi
#if [ "$HIVE_MINER_EXTRA" != "" ]; then
#    FLAGS="$FLAGS --miner.extradata $HIVE_MINER_EXTRA"
#fi

# Import clique signing key.
# TODO
#if [ "$HIVE_CLIQUE_PRIVATEKEY" != "" ]; then
#    # Create password file.
#    echo "Importing clique key..."
#    echo "$HIVE_CLIQUE_PRIVATEKEY" > ./private_key.txt
#
#    # Ensure password file is used when running geth in mining mode.
#    if [ "$HIVE_MINER" != "" ]; then
#        FLAGS="$FLAGS --miner.sigfile private_key.txt"
#    fi
#fi

# If clique is expected enable auto-mine
if [ -n "${HIVE_CLIQUE_PRIVATEKEY}" ] || [ -n "${HIVE_CLIQUE_PERIOD}" ]; then
  FLAGS="$FLAGS --auto-mine"
  if [ -n "${HIVE_CLIQUE_PERIOD}" ]; then
    FLAGS="$FLAGS --dev.block-time ${HIVE_CLIQUE_PERIOD}s"
  fi
fi

# Configure RPC.
FLAGS="$FLAGS --http --http.addr=0.0.0.0 --http.api=admin,debug,eth,net,web3"
# FLAGS="$FLAGS --ws --ws.addr=0.0.0.0 --ws.api=admin,debug,eth,net,web3"

if [ "$HIVE_TERMINAL_TOTAL_DIFFICULTY" != "" ]; then
    JWT_SECRET="7365637265747365637265747365637265747365637265747365637265747365"
    echo -n $JWT_SECRET > /jwt.secret
    FLAGS="$FLAGS --authrpc.addr=0.0.0.0 --authrpc.jwtsecret=/jwt.secret"
fi

# Configure NAT
# FLAGS="$FLAGS --nat none"

# Launch the main client.
echo "Running trin execution with flags: $FLAGS"
RUST_LOG=$TRIN_LOGLEVEL $trin_execution $FLAGS
