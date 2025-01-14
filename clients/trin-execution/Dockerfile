ARG baseimage=kolbyml/trin-execution
ARG tag=latest

FROM $baseimage:$tag as builder

# Install script tools.
RUN apt-get update -y
RUN apt-get install -y bash curl jq

# Add genesis mapper script.
ADD genesis.json /genesis.json
ADD mapper.jq /mapper.jq

# Add the startup script.
ADD trin-execution.sh /trin-execution.sh
RUN chmod +x /trin-execution.sh

# Add the enode URL retriever script.
ADD enode.sh /hive-bin/enode.sh
RUN chmod +x /hive-bin/enode.sh

# Create version.txt
RUN /usr/local/bin/trin-execution --version | sed -e 's/trin-execution \(.*\)/\1/' > /version.txt

# Export the usual networking ports to allow outside access to the node.
EXPOSE 8545 8546 30303 30303/udp 9009/udp

ENTRYPOINT ["/trin-execution.sh"]
