#!/bin/bash
# Enable ATS (Address Translation Services) on all PCI devices
# Takes effect immediately, does not persist across reboots

for i in $(lspci | awk '{print $1}'); do setpci -s $i ECAP_ATS+6.w=8000; done
