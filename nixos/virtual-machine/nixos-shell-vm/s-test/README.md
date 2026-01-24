This is a test host.

For now I'm trying to make a more generic style of saving some stuff like ssh keys and installation script(s). The README, will guide me through how I will install the sops etc like before, but shorter because the machine will boot without propper sops configuration. 


## Sops

Just boot the vm, no additional requirements.

Attach to the live VM with:

```bash
while :; do sleep 2; screen -r s-test ; done
```

Follow the ## impermanence (after setup) section from the README.md in the ~/github/nixos/secrets directory.





