#!/bin/sh
# Watch one full P4 on/off cycle on a dedicated pair: raw ping output plus the
# client's neighbour table every 5 s. Saves everything under results/diag_duty/.
set -u
D=results/diag_duty${STATIC_NEIGH:+_static}; rm -rf $D; mkdir -p $D
docker rm -f tdg-srv tdg-cli >/dev/null 2>&1; docker network rm tdg-net >/dev/null 2>&1
docker network create tdg-net >/dev/null
for c in tdg-srv tdg-cli; do docker run -d --rm --name $c --network tdg-net --cap-add NET_ADMIN tremulator-lab:latest >/dev/null; done
LOOP='while true; do tc qdisc replace dev eth0 root netem delay 125ms loss 2% rate 300kbit; sleep 30; tc qdisc replace dev eth0 root netem loss 100%; sleep 60; done'
for c in tdg-srv tdg-cli; do docker exec -d $c sh -c "$LOOP"; done
SIP=$(docker exec tdg-srv sh -c "ip -4 -o addr show eth0 | awk '{print \$4}' | cut -d/ -f1")
CIP=$(docker exec tdg-cli sh -c "ip -4 -o addr show eth0 | awk '{print \$4}' | cut -d/ -f1")
SMAC=$(docker exec tdg-srv cat /sys/class/net/eth0/address); CMAC=$(docker exec tdg-cli cat /sys/class/net/eth0/address)
if [ "${STATIC_NEIGH:-0}" = 1 ]; then
  docker exec tdg-cli ip neigh replace $SIP lladdr $SMAC dev eth0 nud permanent
  docker exec tdg-srv ip neigh replace $CIP lladdr $CMAC dev eth0 nud permanent
fi
docker exec tdg-cli ping -n -D -i 0.2 -W 1 -w ${SECS:-125} $SIP > $D/ping.txt 2>&1 &
for i in $(seq 1 ${SAMPLES:-25}); do echo "$(date +%s) $(docker exec tdg-cli ip neigh | tr '\n' ' ') | $(docker exec tdg-cli tc qdisc show dev eth0 | head -n1)" >> $D/neigh.txt; sleep 5; done
wait
docker rm -f tdg-srv tdg-cli >/dev/null; docker network rm tdg-net >/dev/null
echo DONE
