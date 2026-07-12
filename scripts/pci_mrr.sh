#!/bin/bash
# Set MaxReadReq to 4096 on all Mellanox PCI devices
# Takes effect immediately, does not persist across reboots

d=$(lspci |grep Mellanox|head -n 1|awk '{print $1}')
if [ "$(lspci -vvv -s $d |grep MaxReadReq|awk '{print $5}')" == "4096" ]; then
  echo "Mellanox devices may have 4k MRR by default. Skip MRR setting."
else
  for d in $(lspci |grep Mellanox|awk '{print $1}'); do
    V=$(setpci -s $d 68.w)
    vDEC=$((16#$V))
    hMASK=8FFF # 4k MRR only # 8F1F if 4k MRR + 512 MPS
    dMASK=$((16#$hMASK))
    dMASKED=$(( vDEC & dMASK ))
    hNV=5000 # 4k MRR only # 5040 if 4k MRR + 512 MPS
    dNV=$((16#$hNV))
    dVAL=$(( dMASKED | dNV ))
    hVAL=$(printf '%x' $dVAL)
    setpci -s $d 68.w=$hVAL
  done
fi
for d in $(lspci |grep Mellanox|awk '{print $1}'); do
  echo -n "$d "; lspci -vvv -s $d |grep MaxReadReq|awk '{print $1, $2, $4, $5}'
done
