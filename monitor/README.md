# elrond-tools / monitor

A simple monitor script that restarts nodes based on a minimal ruleset

## Local usage example

```
curl -LOs https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/monitor/monitor.sh && chmod +x monitor.sh
./monitor.sh --file hosts.txt
```

## Direct usage examples

```
bash <(curl -s -S -L https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/monitor/monitor.sh)
bash <(curl -s -S -L https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/monitor/monitor.sh) --file hosts.txt
```
