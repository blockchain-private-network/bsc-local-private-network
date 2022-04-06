#!/usr/bin/env bash
cd $(dirname $0)
. ./_params.sh

set -e

echo -e "\nStart $N nodes:\n"

rm -f ./transactions.rlp
for ((i=0;i<$N;i+=1))
do
    DATADIR="${PWD}/node$i.datadir"
    rm -fr ${DATADIR}
    mkdir -p ${DATADIR}
    $CLIENT init genesis.json --datadir=${DATADIR}

    PORT=$(($PORT_BASE+$i))
    RPCP=$(($RPCP_BASE+$i))
    WSP=$(($WSP_BASE+$i))
    cat /dev/null > node$i.log
    if [[ $i = 0 ]]
    then
        ($CLIENT \
        --datadir=${DATADIR} \
        --port=${PORT} \
        --nat "extip:127.0.0.1" \
        --mine --miner.etherbase="${ETHERBASE:-"0x888C2Cb5EE08F77f8D2d308E4E9554C101e04C2c"}" --miner.threads=2 \
        --http --http.addr="127.0.0.1" --http.port=${RPCP} --http.corsdomain="*" --http.api="eth,debug,net,admin,web3,personal,txpool" \
        --ws --ws.addr="127.0.0.1" --ws.port=${WSP} --ws.origins="*" --ws.api="eth,debug,net,admin,web3,personal,txpool" \
        --nousb --verbosity=3 >> node$i.log 2>&1)&
    else
        ($CLIENT \
        --datadir=${DATADIR} \
        --port=${PORT} \
        --nat "extip:127.0.0.1" \
        --http --http.addr="127.0.0.1" --http.port=${RPCP} --http.corsdomain="*" --http.api="eth,debug,net,admin,web3,personal,txpool" \
        --ws --ws.addr="127.0.0.1" --ws.port=${WSP} --ws.origins="*" --ws.api="eth,debug,net,admin,web3,personal,txpool" \
        --nousb --verbosity=3 >> node$i.log 2>&1)&
    fi
    echo -e "\tnode$i ok"
done

attach_and_exec() {
    local i=$1
    local CMD=$2
    local RPCP=$(($RPCP_BASE+$i))

    for attempt in $(seq 40)
    do
        if (( attempt > 5 ));
        then 
            echo "  - attempt ${attempt}: " >&2
        fi;

        res=$($CLIENT --exec "${CMD}" attach http://127.0.0.1:${RPCP} 2> /dev/null)
        if [ $? -eq 0 ]
        then
            #echo "success" >&2
            echo $res
            return 0
        else
            #echo "wait" >&2
            sleep 1
        fi
    done
    echo "failed RPC connection to ${NAME}" >&2
    return 1
}


echo -e "\nConnect nodes to ring:\n"
for ((i=0;i<$N;i+=1))
do
    j=$(((i+1) % N))

    enode=$(attach_and_exec $j 'admin.nodeInfo.enode')
    echo "p2p address = ${enode}"

    res=$(attach_and_exec $i "admin.addPeer(${enode})")
    echo -e "connecting node-$i to node-$j, result = ${res}\n"
done

echo -n "Check pre-funded address balance: "

curl --location -g --request POST "http://127.0.0.1:${RPCP_BASE}" \
--header 'Content-Type: application/json' \
--data-raw '{
	"jsonrpc":"2.0",
	"method":"eth_getBalance",
	"params":[
		"0x66615f83A1FE0A17166ddD4E1FE086c733937552", 
		"latest"
	],
	"id":1
}'