# elrond-tools / status

Status script can can check one or multiple nodes at once.

## Arguments
From `./status.sh --help`:

Usage: ./status.sh [option] command
Options:
   --hosts          hosts   a comma separated/delimited list of hosts you want to check status for. E.g: --hosts localhost:8080,localhost:8081,localhost:8082
   --compact                compact output, skipping some unnecessary data
   --no-formatting          disable formatting (colors, bold text etc.), recommended when using the script output in emails etc.
   --debug                  debug mode, output original response etc.
   --help                   print this help

## Local usage example

```
curl -LOs https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/status/status.sh && chmod +x status.sh
./status.sh
./status.sh --hosts someremotehost.com:8080,anotherremotehose.com:8080
```

## Direct usage examples

bash <(curl -s -S -L https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/status/status.sh)
bash <(curl -s -S -L https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/status/status.sh) --hosts someremotehost.com,anotherremotehose.com:8081
